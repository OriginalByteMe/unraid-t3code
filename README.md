# unraid-t3code

An unofficial Unraid template and Docker image for
[T3 Code](https://t3.codes) ([source](https://github.com/pingdotgg/t3code)),
the open-source control surface for coding agents such as Claude Code, Codex,
Cursor, OpenCode and Pi. The container runs `t3 serve`, T3 Code's headless
server, so the agents, projects, worktrees and terminals live on your server
while the T3 Code web, desktop and phone apps connect to it. This project is not
affiliated with T3 Tools.

The image is rebuilt whenever T3 Code publishes a release, because T3 Code
clients refuse to connect to a server whose protocol doesn't match their own,
and that can change with any release.

## What this image adds to T3 Code

- Starts `t3 serve` as Unraid's usual 99:100 account; `t3 pair` in the Console
  prints a pairing token for each device.
- Installs agent CLIs by name, for example `claude codex`, into the Data folder
  so they survive updates.
- Clones a list of GitHub repositories into a Projects folder and adds them to
  T3 Code as projects.
- Offers bash, zsh with optional Oh My Zsh, or fish for the terminals, plus tmux.
- Ships the libraries and fonts T3's built-in browser needs, which minimal
  containers lack.
- Works with Unraid's **Use Tailscale** switch, so any device on your tailnet can
  connect, over HTTPS too.
- Can hand the agents the Docker or libvirt socket, so they can run their own
  containers and VMs.

## Getting started

1. **Install the template.** Until it is in Community Apps, copy it onto the
   flash drive from the Unraid terminal:

   ```sh
   curl -fsSL -o /boot/config/plugins/dockerMan/templates-user/my-T3-Code.xml \
     https://raw.githubusercontent.com/OriginalByteMe/unraid-t3code/main/templates/t3code.xml
   ```

   Then on the Docker tab choose **Add Container** and pick **T3-Code** from the
   user templates.
2. **Point Projects at your code.** The default is a folder inside appdata; any
   share works.
3. **List your repositories.** Put them under **Repositories** as `owner/name`,
   and fill in **GitHub token** if any are private. They are cloned and added to
   T3 Code on the first start, so your projects are waiting when you connect.
4. **Pick your agents and shell**, for example `claude codex` under **Agents**,
   and `zsh` with **Oh My Zsh** set to `true`.
5. **Apply and pair.** Open the container's **Console** and run `t3 pair`; it
   prints a **Token**. Click the container's **WebUI** (`http://<server>:3773`),
   paste the token, and that browser is paired. In the desktop or phone app,
   choose **Add environment** and enter `http://<server>:3773` with the token.
   Each token works once and expires after 5 minutes; run `t3 pair` again for
   the next device. See [Pairing](#pairing) for why the links it prints don't
   work as they are.
6. **Log in to each agent once.** In the Console run, for example, `claude` and
   then `/login`, or `codex login --device-auth`. Codex can also sign in from
   **Settings → Providers** in T3 Code. Logins are kept in the Data folder, so
   updates don't log you out.

## Pairing

With Unraid's default bridge network, T3 Code only sees the container's
internal address, so the connection string, pairing URL and QR code that
`t3 serve` and `t3 pair` print point at something like `172.17.0.2`, which no
other device can reach. The token in them is fine. Use it with the server's real
address as in step 5, or replace the address in the pairing URL with your
server's LAN or Tailscale address before opening it.

The token the server prints at startup expires after 5 minutes too, which is
why step 5 makes a fresh one. Revoke paired devices in **Settings → Sharing &
access**, or with `t3 auth session list` and `t3 auth session revoke <id>` in the
Console.

To reach the server from outside your network without Tailscale, run
`t3 connect link --headless` in the Console, sign in to T3 Connect with the code
it prints, then restart the container. Your devices then find it through your
T3 Connect account.

## Tips

- **Get your repositories in early.** Fill in **Repositories** before the first
  start. Adding one later and applying clones only the new one; existing clones
  are never touched or deleted. You can also `git clone` into `/projects` from
  the Console and add it in T3 Code.
- **Use `owner/name` or HTTPS URLs with a GitHub token.** The token is set up
  for both git and `gh`, so agents can push and open pull requests. SSH URLs
  need a key in `~/.ssh` (in the Data folder) and github.com in `known_hosts`;
  running `ssh -T git@github.com` once from the Console adds it.
- **Set Git user name and email** in the advanced view, so the agents' commits
  carry your name.
- **Keep Data and Projects on a fast pool.** Worktrees, `node_modules` and agent
  logs are lots of small files, which a cache pool or SSD handles far better
  than the parity array.
- **Cap its memory** by adding `--memory=8g` to **Extra Parameters** next to
  `--shm-size=1g`, so one runaway build can't starve the rest of the server.
  Keep `--shm-size=1g`: T3's browser crashes on larger pages with Docker's
  default 64 MB of shared memory.
- **Turn off key expiry** for the `t3code` machine in the Tailscale admin
  console, or it drops off your tailnet after 180 days.

## Settings

| Setting | Variable | What it does |
|---|---|---|
| T3 Code port | 3773 | Port the web UI and the apps connect to |
| Data | `/home/t3code` | Threads, settings, paired devices, worktrees, agent logins and shell settings |
| Projects | `/projects` | Your repositories. Add projects from here in T3 Code; point it at any share |
| GitHub token | `GH_TOKEN` | Used by git and `gh` for clones, pushes and pull requests |
| Repositories | `GIT_REPOS` | Space-separated `owner/name` or clone URLs, cloned once into `/projects` and added to T3 Code |
| Agents | `AGENTS` | Agent CLIs installed once into the Data folder; they update themselves from there. See the list below |
| Shell | `SHELL` | `bash`, `zsh` or `fish` for T3 Code's terminals and the console. `tmux` is installed too |
| Oh My Zsh | `OH_MY_ZSH` | `true` installs Oh My Zsh into the Data folder on the next start, keeping an existing `.zshrc` as `.zshrc.pre-oh-my-zsh` |
| Git user name / email | `GIT_USER_NAME`, `GIT_USER_EMAIL` | Identity on the agents' commits |
| Docker socket | `/var/run/docker.sock` | Off unless you fill it in. See below |
| libvirt socket | `/var/run/libvirt/libvirt-sock` | Off unless you fill it in. See below |
| PUID / PGID | `PUID`, `PGID` | Account the agents run as, 99:100 by default like other Unraid apps |

T3 Code reads its own `T3CODE_*` environment variables too; add one with
**Add another Path, Port, Variable, Label or Device** if you need it.

The agents run as that unprivileged account. The Console button drops you into
its shell too; use `sh` instead of `bash` if you need root inside the container.

## Agents

**Agents** takes these names, each installed from its vendor's official npm
package; any other word is installed as an npm package of that name. Node and
Bun are both in the image, so Bun-based CLIs such as omp run too.

| Name | npm package | In T3 Code |
|---|---|---|
| `claude` | `@anthropic-ai/claude-code` | Provider |
| `codex` | `@openai/codex` | Provider |
| `opencode` | `opencode-ai` | Provider |
| `pi` | `@earendil-works/pi-coding-agent` | Provider |
| `gemini` | `@google/gemini-cli` | Local ACP command |
| `omp` | `@oh-my-pi/pi-coding-agent` | Terminals |

T3 Code's other providers have their own installers. Run them from the Console;
they install into your home folder, which is the Data folder, so they survive
updates:

- Cursor: `curl https://cursor.com/install -fsS | bash`, then `agent login`.
- fx: `curl -fsSL https://fx.sh/setup.sh | bash`, then `fx login`.
- Grok Build and Muse Code: follow the vendor's instructions, linked from
  T3 Code's [provider setup](https://github.com/pingdotgg/t3code/blob/main/docs/user/install.md#providers).
- Antigravity, and agents from the ACP Registry, install from **Settings →
  Providers** in T3 Code.

## Docker and VM access

Fill in the **Docker socket** path to let agents run `docker`, for example to
start a database for the project they are working on or a sandbox container of
their own. Fill in the **libvirt socket** path to let them start and manage VMs
with `virsh`.

Either socket gives the agents root-level control of the whole server: anything
that can start a container or define a VM can mount your shares, read every
other app's data, or stop other containers and VMs. Only map them when you trust
every agent and prompt that runs in this container. Containers the agents start
are not limited by this container's memory settings, so give them `--memory`
caps yourself.

## Tailscale

The template is set up for Unraid's **Use Tailscale** switch (Unraid 7 or later):
the hostname defaults to `t3code` and Tailscale's state lives in the Data folder.
Turn it on, apply, and approve the container from the link in its log. Unraid
also turns on **Tailscale Serve** for the WebUI port, which gives the container
an HTTPS address such as `https://t3code.your-tailnet.ts.net` (enable MagicDNS
and HTTPS for your tailnet first). Pair with that address and a token as in
step 5. HTTPS is what the hosted web app at app.t3.codes needs; the desktop and
phone apps also work over plain `http://t3code:3773`.

## Updating

Unraid shows an update on the Docker tab when a new image is out, which happens
when a pull request bumping T3 Code's version is merged here. Update the T3 Code
apps on your devices at about the same time: a client and server on different
versions refuse to connect, and say which side to update. The apps' **Update
server** button can't update this container; update it from the Docker tab
instead, and don't run `t3 update` in the Console, since the container always
starts the image's own version.

To stay on one version, change the Repository field to a version tag such as
`ghcr.io/originalbyteme/unraid-t3code:0.1.5`. Going back to an older version
than you have run may not work, because newer versions migrate the database.

Updating or restarting the container interrupts running agents and terminals.
Threads, settings and worktrees stay in the Data folder, and T3 Code resumes
supported threads after the restart (**Settings → Maintenance → Continue
threads after restarts**).

## Building it yourself

```sh
docker build -t unraid-t3code .
```

Every push runs `.github/workflows/build.yml`, which builds the image and checks
that it honours PUID and PGID, can use a mapped Docker socket, installs agents
by name (omp running on Bun), runs a headless Chrome with the shipped libraries
and fonts, serves the web UI, clones a repository into `/projects` and adds it
to T3 Code once across restarts, and gives the account zsh with Oh My Zsh.

The T3 Code version is pinned in the Dockerfile. Every 6 hours
`.github/workflows/t3-bump.yml` checks T3 Code's stable releases and, when there
is a newer one, opens a pull request that bumps the pin and runs the build
against it. Merging that pull request publishes the image to GHCR and to Docker
Hub as `originalbyteme/unraid-t3code`, where Community Apps reads its Last
Update date; closing it skips that version. A manual run of `build.yml` with
**publish** ticked republishes the pinned version, for example after a
Dockerfile change.

## Credits

T3 Code is made by [T3 Tools](https://github.com/pingdotgg/t3code) and is MIT
licensed; the icon is T3 Code's, Copyright (c) 2026 T3 Tools Inc., used under
[T3 Code's MIT license](https://github.com/pingdotgg/t3code/blob/main/LICENSE).
This repository is MIT licensed and follows the layout of
[unraid-orca](https://github.com/OriginalByteMe/unraid-orca).
