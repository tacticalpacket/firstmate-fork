# Round 2 verification: pane PATH now resolves shasum, and the test oracle can fail

Target commit: `7812f28` (`no-mistakes(test): carry perl script dirs in pane PATH, fix non-login oracle`).
Host: Arch (Linux), herdr 0.9.1 at `/usr/local/bin/herdr`, `/usr/bin/core_perl/shasum` present.

## 1. Real herdr pane, incident launcher shape (end-to-end)

Same script and isolation as round 1 (`real-herdr-pane-env-e2e.sh`): a throwaway
`XDG_CONFIG_HOME`, so this run's server has its own api socket and cannot see or stop the
host's live `default` / `ops` servers - both were listed running before and after and never
changed. Launcher: `/usr/bin/env -i` with `SHELL=/bin/sh`, truncated
`PATH=/usr/local/bin:/usr/bin:/bin` (no `core_perl`), and a task pin to task-b.

| probe typed into a real pane | base `3b68997` (round 1) | target `7812f28` |
| --- | --- | --- |
| `SHELL` | `/bin/sh` | `/usr/bin/bash` (the uid's passwd shell) |
| shell process | `sh`, prompt `sh-5.3$` | `bash`, the operator's own prompt + mise shims |
| `command -v shasum` | `UNREACHABLE` | `/usr/bin/core_perl/shasum` |
| `shasum -a 256 /etc/hostname; echo $?` | **127** | **0** |
| `pane-PATH` tail | - | `...:/bin:/sbin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl` |
| `FM_CREW_STATE_META_OVERRIDE` | `.../task-b.meta` (leaked) | `<none>` |
| `fm-crew-state.sh task-a` | task-b's answer (`worktree gone`) | `no metadata for task-a` - follows task-a |
| pane shell is a login shell | no | no (`argv0 /usr/bin/bash`, cmdline `/usr/bin/bash`) |

So both measured consequences of the 2026-09-26 incident are closed in a real pane: the
passwd shell with its startup config, and `shasum` resolving with exit 0 even though the
pane shell is still non-login (herdr 0.9.1's behaviour, which the frozen config cannot
change) - the baseline PATH now carries the perl script directories itself.

Transcript: `verify-target-7812f28-real-pane.txt`.

## 2. The fixed test oracle can actually fail

The round-1 finding was that the assertion forced `-l -c` on the recorded shell, an
invocation herdr never uses, so a login profile supplied `core_perl` and the assertion could
not fail. Measured both ways, with the three perl directories temporarily removed from the
source baseline (library restored immediately after; the worktree is clean):

| oracle | baseline WITH perl dirs (target) | baseline WITHOUT them (the defect) |
| --- | --- | --- |
| old `-l -c` (login shell) | ok | **ok** - green despite an unusable pane PATH |
| new `-i -c` (interactive, non-login - what herdr actually starts) | ok | **not ok** - "a pane of this server cannot run shasum; the launched PATH ('...:/bin:/sbin') leaves it unreachable in a pane's non-login shell" |

The same flip holds for `tests/fm-herdr-lab.test.sh`'s provision case. The interactive probe
matches the real pane on this host: `fm_test_passwd_shell` resolves `/usr/bin/bash`, the same
shell the real pane reported, and the operator's `~/.bashrc` does not add `core_perl` (the
pane PATH shows it only once, from the baseline), so the assertion is load-bearing on the
source baseline rather than on the operator's rc file.

## 3. Server starts through the cli wrapper are refused

`herdr-cli-server-refusal.txt`: `fm_backend_herdr_cli default server start` now prints
`error: fm_backend_herdr_cli forbids starting a herdr server; use fm_backend_herdr_server_ensure,
which launches it through the shared clean environment` and exits 1, matching the sibling
policy in `fm_herdr_lab_cli`.
