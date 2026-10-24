// Copyright 2026 Tom Ballard. MIT License.
#pragma once
#include <stdint.h>
#include <stdbool.h>

uint64_t omarchy_pair_start(const char *display_name, const char *identity, const char *output_path);
// The returned UTF-8 JSON contains progress, Bonjour records and the PIN, never signing keys.
// The caller owns the result and must free it with omarchy_pair_free_string.
char *omarchy_pair_status(uint64_t handle);
void omarchy_pair_cancel(uint64_t handle);
void omarchy_pair_free_string(char *value);
bool omarchy_debugger_attached(void);
bool omarchy_development_signed(void);
