// Copyright 2026 Tom Ballard. MIT License.
use idevice::remote_pairing::{PairableHost, PairableHostInfo, RpPairingFile, RpPairingSocket};
use serde::Serialize;
use std::{
    collections::BTreeMap,
    ffi::{c_char, CStr, CString},
    fs::{self, OpenOptions},
    io::Write,
    net::Ipv4Addr,
    path::Path,
    sync::{atomic::{AtomicU64, Ordering}, Arc, Mutex, OnceLock},
    time::Duration,
};
use tokio::{net::TcpListener, sync::Notify};

#[derive(Clone, Default, Serialize)]
struct Status {
    phase: String,
    port: u16,
    service: String,
    txt: BTreeMap<String, String>,
    code: Option<String>,
    error: Option<String>,
    #[serde(skip)]
    cancelled: bool,
}

struct Session {
    state: Mutex<Status>,
    cancelled: Notify,
}

static SESSIONS: OnceLock<Mutex<BTreeMap<u64, Arc<Session>>>> = OnceLock::new();
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

fn sessions() -> &'static Mutex<BTreeMap<u64, Arc<Session>>> {
    SESSIONS.get_or_init(Mutex::default)
}

fn session(handle: u64) -> Option<Arc<Session>> {
    sessions().lock().ok()?.get(&handle).cloned()
}

fn update(session: &Session, change: impl FnOnce(&mut Status)) {
    if let Ok(mut state) = session.state.lock() {
        if !state.cancelled { change(&mut state); }
    }
}

// Keep cancellation and commit under the same lock: cancelling a session must
// never overwrite an existing pairing with a late result from its worker.
fn commit(session: &Session, output: &Path, bytes: &[u8], handle: u64) -> Result<(), String> {
    let mut state = session.state.lock().map_err(|_| "Pairing state unavailable")?;
    if state.cancelled { return Ok(()); }
    let partial = output.with_extension(format!("{handle}.partial"));
    let result = (|| -> std::io::Result<()> {
        let mut options = OpenOptions::new();
        options.write(true).create_new(true);
        #[cfg(unix)] {
            use std::os::unix::fs::OpenOptionsExt;
            options.mode(0o600);
        }
        let mut file = options.open(&partial)?;
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&partial, output)?;
        Ok(())
    })();
    if result.is_err() { let _ = fs::remove_file(&partial); }
    result.map_err(|e| format!("Could not save pairing: {e}"))?;
    state.phase = "complete".into();
    state.code = None;
    Ok(())
}

async fn pair(session: Arc<Session>, name: String, identity: String, output: String, handle: u64) -> Result<(), String> {
    let listener = TcpListener::bind((Ipv4Addr::UNSPECIFIED, 0)).await
        .map_err(|e| format!("Could not listen for pairing: {e}"))?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let mut file = RpPairingFile::generate(&identity);
    let info = PairableHostInfo::generate(name, "Mac17,7");
    let records = info.mdns_txt_records(&file.identifier);
    update(&session, |state| {
        state.phase = "waiting".into();
        state.port = port;
        state.service = file.identifier.clone();
        state.txt = records.into_iter().collect();
    });
    let exchange = async {
        let (stream, _) = listener.accept().await.map_err(|e| e.to_string())?;
        let mut host = PairableHost::new(RpPairingSocket::new_device(stream), info);
        host.accept(&mut file, |pin| {
            update(&session, |state| {
                state.phase = "code".into();
                state.code = Some(pin);
            });
            async {}
        }).await.map_err(|e| format!("Pairing failed: {e}"))?;
        commit(&session, Path::new(&output), &file.to_bytes(), handle)
    };
    tokio::select! {
        result = exchange => result,
        _ = session.cancelled.notified() => Ok(()),
        _ = tokio::time::sleep(Duration::from_secs(300)) => Err("Pairing timed out. Start again and select iPhomarchy in Developer Mode settings.".into()),
    }
}

unsafe fn argument(value: *const c_char) -> Option<String> {
    if value.is_null() { return None; }
    CStr::from_ptr(value).to_str().ok().filter(|s| !s.is_empty() && s.len() < 4096).map(str::to_owned)
}

/// The input pointers must remain valid for this call only. They are copied
/// before the worker starts; callers can release them immediately afterwards.
#[no_mangle]
pub unsafe extern "C" fn omarchy_pair_start(name: *const c_char, identity: *const c_char, output: *const c_char) -> u64 {
    let (Some(name), Some(identity), Some(output)) = (argument(name), argument(identity), argument(output)) else { return 0; };
    let session = Arc::new(Session {
        state: Mutex::new(Status { phase: "starting".into(), ..Default::default() }),
        cancelled: Notify::new(),
    });
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    {
        let Ok(mut all) = sessions().lock() else { return 0; };
        // One listener per app. An accidental repeated tap cannot leak workers.
        if !all.is_empty() { return 0; }
        all.insert(handle, session.clone());
    }
    let worker = session.clone();
    let spawn = std::thread::Builder::new().name("omarchy-pairing".into()).spawn(move || {
        let result = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
            tokio::runtime::Builder::new_current_thread().enable_all().build()
                .map_err(|e| e.to_string())?.block_on(pair(worker.clone(), name, identity, output, handle))
        })).unwrap_or_else(|_| Err("The pairing service stopped unexpectedly. Please retry.".into()));
        if let Err(message) = result {
            update(&worker, |state| {
                state.phase = "failed".into(); state.code = None; state.error = Some(message);
            });
        }
    });
    if spawn.is_err() {
        omarchy_pair_cancel(handle);
        return 0;
    }
    handle
}

#[no_mangle]
pub extern "C" fn omarchy_pair_status(handle: u64) -> *mut c_char {
    let text = session(handle).and_then(|s| s.state.lock().ok().and_then(|state| serde_json::to_string(&*state).ok()));
    text.and_then(|s| CString::new(s).ok()).map(CString::into_raw).unwrap_or(std::ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn omarchy_pair_cancel(handle: u64) {
    let removed = sessions().lock().ok().and_then(|mut all| all.remove(&handle));
    if let Some(session) = removed {
        if let Ok(mut state) = session.state.lock() { state.cancelled = true; state.code = None; }
        // notify_one retains a permit when the worker has not started polling.
        session.cancelled.notify_one();
    }
}

#[no_mangle]
pub unsafe extern "C" fn omarchy_pair_free_string(value: *mut c_char) {
    if !value.is_null() { drop(CString::from_raw(value)); }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancelled_pairing_preserves_existing_file() {
        let path = std::env::temp_dir().join(format!("omarchy-pairing-test-{}", std::process::id()));
        fs::write(&path, b"previous pairing").unwrap();
        let s = Session { state: Mutex::new(Status { cancelled: true, ..Default::default() }), cancelled: Notify::new() };
        commit(&s, &path, b"late result", 1).unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"previous pairing");
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn committed_keys_are_private_and_never_in_status() {
        let path = std::env::temp_dir().join(format!("omarchy-pairing-secret-test-{}", std::process::id()));
        let s = Session { state: Mutex::new(Status::default()), cancelled: Notify::new() };
        commit(&s, &path, b"private-key-material", 2).unwrap();
        assert_eq!(fs::read(&path).unwrap(), b"private-key-material");
        #[cfg(unix)] {
            use std::os::unix::fs::PermissionsExt;
            assert_eq!(fs::metadata(&path).unwrap().permissions().mode() & 0o777, 0o600);
        }
        let status = serde_json::to_string(&*s.state.lock().unwrap()).unwrap();
        assert!(!status.contains("private-key-material"));
        assert!(status.contains("complete"));
        fs::remove_file(path).unwrap();
    }

    #[test]
    fn invalid_handles_and_null_arguments_are_safe() {
        assert!(omarchy_pair_status(u64::MAX).is_null());
        omarchy_pair_cancel(u64::MAX);
        unsafe {
            assert_eq!(omarchy_pair_start(std::ptr::null(), std::ptr::null(), std::ptr::null()), 0);
            omarchy_pair_free_string(std::ptr::null_mut());
        }
    }
}
