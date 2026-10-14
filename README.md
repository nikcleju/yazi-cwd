# yazi-cwd

Keep an interactive Zsh shell and a running Yazi instance in the same directory.
Shell directory changes are sent to Yazi; Yazi directory and active-tab changes
are followed by the shell while its prompt is active. Partially typed commands
are preserved. Updates received during a foreground command are applied when
the shell returns to its prompt.

## Requirements

- Zsh (tested with 5.9).
- Yazi and its `ya` command, plus `jq`, on your `PATH`.
- A compatible **getcwd** plugin enabled in Yazi. This companion plugin is not
  included in this repository: it must subscribe to `get-active-cwd` and reply
  to the supplied numeric `client_id` with `return-active-cwd` containing
  `{ "cwd": "..." }` for the active tab.

If your companion plugin is installed as `getcwd.yazi` in Yazi's configuration
`plugins` directory, enable it in Yazi's `init.lua`:

```lua
require("getcwd"):setup()
```

Restart Yazi after enabling the companion plugin. The shell must be able to
access the reported directories locally.

## Installation

### Oh My Zsh

Place this repository at `${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/yazi-cwd`
and add `yazi-cwd` to the existing plugin list in `~/.zshrc`:

```zsh
plugins=(git yazi-cwd)
```

Keep your other plugins in that list. Start a new shell after changing it.

### Plain Zsh

Add this to `~/.zshrc`, using the repository's actual path:

```zsh
source /path/to/yazi-cwd/yazi-cwd.plugin.zsh
```

## Usage

Start Yazi, then run in your shell:

```zsh
yazi-connect
```

One compatible instance is selected automatically; multiple instances produce
a numbered menu. Press Enter to cancel. Connecting changes the shell to the
selected instance's active directory and enables bidirectional synchronization.
Run `yazi-connect` again to choose another instance.

| Command / key | Action |
| --- | --- |
| `cd /some/directory` | Change the shell directory and update the paired Yazi. |
| `cdy` | Pull the paired Yazi's active directory into the shell. |
| `cdy <instance-id>` | Pull another instance's directory once, without changing the pairing. |
| **Ctrl-G** | Run `cdy` at the prompt; replaces the existing Ctrl-G binding. |

The selected ID is stored in `YAZI_CWD_ID`. When it is unset or empty, the plugin
uses an inherited `YAZI_ID`, allowing shells launched inside Yazi to follow that
instance without explicit pairing. Failed cwd queries leave the shell directory
unchanged; later relevant events can retry synchronization.

Listeners are cleaned up when the shell exits or the plugin is re-sourced.
`yazi-cwd-start` and `yazi-cwd-stop` manage the listener manually; stopping it is
temporary because the next prompt starts it again if a target ID is still set.

## Tests

From the repository directory, run:

```sh
./test
```

Requires **Python 3, Zsh, and jq**. The runner checks all Zsh files for syntax
errors, then runs the regression suite. It exits nonzero on failure and also
works when invoked by its full path from another directory.

Tests mock `ya`; no running Yazi instance, companion plugin, Python packages,
or network access is needed. They cover exact trailing-newline paths, optional
variables with `NO_UNSET`, failed-query retries, and unchanged state on failure.
They are not a substitute for testing live Yazi or interactive terminal behavior.

## Troubleshooting

- **No compatible instances:** ensure Yazi is running and the companion getcwd
  plugin is enabled in that instance.
- **Missing dependency:** ensure `ya` and `jq` are on the shell's `PATH`.
- **No cwd reply within five seconds:** check that the selected instance is
  still running and its companion plugin implements the reply protocol above.
- **Directory is not accessible:** the reported cwd must be an existing local
  directory accessible to the shell.
