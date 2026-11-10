# Networking

Three systems share one tailnet: Windows, the WSL VM behind it, and the Mac.
The Mac is a first-class Tailscale node. The WSL VM is not. That asymmetry
explains every address in the setup.

## Topology

```text
Tailnet
  anix (Tailscale node on Windows)
    WSL2, mirrored networking
      anix (NixOS-WSL hostname, 172.x inside the VM)
      nfsd on TCP 2049
  amac (Tailscale on macOS)
    NFS client of anix:/  ->  /Users/winona/src
    sshd on TCP 22
```

WSL runs in mirrored networking mode. It shares the Windows interfaces and the
Windows tailnet address. A second Tailscale client inside WSL would conflict
with the Windows client, so there is only one.

The Windows Tailscale node is named `anix`, the same as the WSL hostname. From
the Mac, `anix` resolves to the Windows node; from WSL, `anix` resolves to the
local host. The Mac mounts `anix:/`, and the Windows node forwards TCP 2049 to
the WSL NFS server. The WSL host reaches the Mac at `amac` through MagicDNS,
which Windows provides to WSL.

## Addresses

| From | To | Address | Used for |
| --- | --- | --- | --- |
| WSL | Mac | `amac` | SSH, `darwin-rebuild`, remote builds |
| Mac | WSL NFS | `anix` (Windows node) or its `100.x` | NFSv4.1 |
| Mac | WSL NFS | `amac` client name | Export scope |
| Windows | Mac | `amac` | Tailscale only |

`anix` is the Windows node name and the NFS server name for the Mac. `amac` is
the Mac's MagicDNS name and the only client the export accepts.

## WSL networking

`.wslconfig` on Windows sets the mode:

```ini
[wsl2]
memory=16GB
processors=8
swap=8GB
networkingMode=mirrored
dnsTunneling=true
autoProxy=true

[general]
instanceIdleTimeout=-1

[experimental]
autoMemoryReclaim=gradual
sparseVhd=true
```

Mirrored mode gives WSL the Windows interfaces and the Windows Tailscale
address. `dnsTunneling` sends DNS through Windows, so MagicDNS names resolve
inside WSL. `instanceIdleTimeout=-1` keeps the distro from shutting down while
NFS and builds depend on it.

Inbound traffic reaches WSL only when the Hyper-V firewall allows it. A normal
Windows firewall rule does not cover the WSL VM. Run this elevated on Windows:

```powershell
New-NetFirewallHyperVRule `
  -Name "WSL-nfsd-2049" `
  -DisplayName "WSL nfsd TCP 2049" `
  -Direction Inbound `
  -Action Allow `
  -VMCreatorId "{40E0AC32-46A5-438A-A0B2-2B479E8F2E90}" `
  -Protocol TCP `
  -LocalPorts 2049
```

Confirm the WSL creator GUID on the machine:

```powershell
Get-NetFirewallHyperVVMCreator
```

If the Tailscale interface is classified as Public, add `-Profiles Any`, or set
the Tailscale network to Private. The NixOS firewall must also allow TCP 2049
from the Tailscale CGNAT range, `100.64.0.0/10`.

## NFS

The WSL host exports `~/src` as the NFSv4.1 pseudo-root:

```nix
services.nfs.server.enable = true;
services.nfs.server.createMountPoints = true;
services.nfs.server.exports = ''
  /home/winona/src  amac(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000,insecure,fsid=0)
'';
```

`fsid=0` makes the export the pseudo-root, so the Mac mounts `windows-node:/`.
`all_squash` maps every request to uid 1000 and gid 1000 on the WSL host.
`insecure` accepts the source port macOS uses. The export is scoped to `amac`,
the Mac's MagicDNS name; the firewall allows 2049 from the Tailscale range.

The Mac mount uses NFSv4.1 only:

```text
vers=4.1,resvport,rw,noowners,hard,intr,rsize=131072,wsize=131072,bg
```

`noowners` tells macOS to ignore the numeric owner on the wire. `hard` keeps
retrying instead of returning I/O errors. `intr` lets a signal interrupt a hung
call. `bg` retries the mount in the background when the server is not ready.

If the Mac rejects `vers=4.1`, mount with `vers=4` against the same export and
check reads and writes. Do not fall back to NFSv3; the export uses `fsid=0`.

NFSv4.1 needs only TCP 2049. The host configuration disables NFSv3. The NixOS
module still starts rpcbind and mountd; they are not opened in the firewall.
There is no SMB fallback.

## File watching

NFS gives the Mac a consistent view of file contents, but macOS file watchers
do not reliably see changes made on the WSL host. Tools that depend on inotify
or FSEvents can miss remote edits. Keep `target/`, `DerivedData`, and
`node_modules` on local disk, and restart a watcher after a large change from
the other host.

## Remote builder

The WSL host sends Darwin builds to the Mac over SSH:

```nix
nix.distributedBuilds = true;
nix.settings.builders-use-substitutes = true;
nix.buildMachines = [{
  hostName = "amac";
  sshUser = "winona";
  sshKey = "/etc/nix/mac-builder";
  systems = [ "x86_64-darwin" ];
  protocol = "ssh-ng";
  maxJobs = 6;
  supportedFeatures = [ "big-parallel" ];
}];
```

The Mac enables SSH and trusts `winona`:

```nix
services.openssh.enable = true;
nix.settings.trusted-users = [ "winona" ];
```

`ssh-ng` talks to the remote `nix-daemon`. `trusted-users` is required because
the daemon accepts build requests from that user. It is also root-equivalent on
the Mac; this is the accepted cost of building as the login user.

The builder key is the `mac-builder-key` sops secret. The private key is
installed at `/etc/nix/mac-builder` with mode `0400` on WSL. The public key goes
in `winona`'s `~/.ssh/authorized_keys` on the Mac, managed by Home Manager. Add the Mac host key to root's
`known_hosts` on WSL, for example with `programs.ssh.knownHosts`, or the
nix-daemon SSH fails host-key verification.

## code-server

`code-server` runs on anix as a systemd service. It serves the same
`/home/winona/src` tree as ttt at `http://anix:8080`. The password is the
`code-server-password` sops secret; the service reads it through
`LoadCredential`, so it never appears in argv or the Nix store.

The service binds `0.0.0.0:8080`. The nftables input rule accepts 8080 only
from `100.64.0.0/10`, and the Windows bootstrap opens 8080 on the Hyper-V
firewall. The Mac opens `http://anix:8080`; `http://anix:8080/healthz` is the
health check.

The Mac runs VS Code desktop against `/Users/winona/src` over NFS. code-server
is browser-only; it cannot attach to the desktop app. Use `scripts/ttt-handoff`
or the Herdr sidebar actions to open the same file in either editor.

## Ports

| Port | Host | Direction | Purpose |
| --- | --- | --- | --- |
| 2049/tcp | WSL via Windows | Mac to WSL | NFSv4.1 |
| 8080/tcp | WSL via Windows | Mac to WSL | code-server |
| 22/tcp | Mac | WSL to Mac | SSH, `darwin-rebuild`, `ssh-ng` |
| 41641/udp | Windows, Mac | Tailscale | NAT traversal |

anix generates and holds the host key used by sops with
`services.openssh.generateHostKeys`; sshd does not run. The firewall stays
closed, and the Mac never pushes to the WSL host. No inbound SSH is needed on
WSL.

## Failure modes

- Tailscale is down on Windows: the Mac cannot reach NFS, and WSL cannot resolve
  `amac`.
- The Hyper-V firewall rule is missing: TCP 2049 connects inside WSL but not
  from the Mac.
- The NixOS firewall blocks 2049: the export exists, but the Mac gets
  `Operation timed out`.
- WSL is not started: the `anix-wsl` logon task starts it. Check Task
  Scheduler if the NFS server is absent after a Windows reboot.
- WSL is stopped or idle: the mount hangs until the VM returns.
  `instanceIdleTimeout` and the `bg` mount option reduce the impact.
- MagicDNS is off: `amac` does not resolve. Use the Tailscale IP as a temporary
  fallback.
- The export is not scoped to `amac`: `exportfs` shows the wrong client, and
  the Mac gets `Permission denied`.
