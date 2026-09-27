# Real herdr pane: before vs after, same incident launcher

Installed herdr 0.9.1 on the host. Every call ran with `XDG_CONFIG_HOME` pointed at a
throwaway scratch root, so this run's server had its own api socket and could not see or
stop the host's live `default` / `ops` servers - both were listed running before and after
each run and never changed.

Launcher in both runs: `/usr/bin/env -i` with `SHELL=/bin/sh`, a truncated
`PATH=/usr/local/bin:/usr/bin:/bin` (no `/usr/bin/core_perl`), and a task pin to task-b
(`FM_CREW_STATE_META_OVERRIDE`, `FM_CREW_STATE_STATUS_OVERRIDE`, `FM_SNAPSHOT_CACHE_DIR`).
Probes were typed into a real task pane of the server that launch produced.

| probe in a real pane | base 3b68997 | target 01af3fd |
| --- | --- | --- |
| `SHELL` | `/bin/sh` | `/usr/bin/bash` (the uid's passwd shell) |
| shell process | `sh`, prompt `sh-5.3$` | `bash`, the operator's own prompt + mise shims from `~/.bashrc` |
| `FM_CREW_STATE_META_OVERRIDE` | `.../state/task-b.meta` (leaked) | `<none>` |
| `fm-crew-state.sh task-a` | `state: unknown · source: none · worktree gone (torn down?)` - task-b's answer | `state: unknown · source: none · no metadata for task-a` - follows task-a |
| `command -v shasum` | `UNREACHABLE` | `UNREACHABLE` |
| `shasum -a 256 ...; echo $?` | `127` | `127` |
| pane shell is a login shell | no (`$0=/bin/sh`) | no (`$0=/usr/bin/bash`, cmdline `/usr/bin/bash`) |

Transcripts: `before-fix-real-herdr-pane.txt`, `after-fix-real-herdr-pane.txt`.

A second pair ran the same probes with a launcher whose PATH *did* contain
`/usr/bin/core_perl` (`before-fix-launcher-had-core_perl.txt`,
`after-fix-launcher-had-core_perl.txt`):

| probe in a real pane | base 3b68997 | target 01af3fd |
| --- | --- | --- |
| pane `PATH` | `/usr/local/bin:/usr/bin:/usr/bin/core_perl:/bin` (inherited) | the source-defined baseline, which does not list `core_perl` |
| `shasum -a 256 ...; echo $?` | `0`, resolved `/usr/bin/core_perl/shasum` | `127`, `UNREACHABLE` |

So the pane shell herdr 0.9.1 starts is interactive but NOT a login shell, which means
`/etc/profile.d/perlbin.sh` never runs and nothing re-adds `/usr/bin/core_perl` after the
baseline PATH replaces the launcher's.

Script: `real-herdr-pane-env-e2e.sh` (run with `ROOT=<worktree> LAUNCH_PATH=...`).
