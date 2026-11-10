# Networking

Three systems share one tailnet: Windows, the WSL VM behind it, and the Mac.
The Mac is a first-class Tailscale node. The WSL VM is not. That asymmetry
explains every address in the setup.

## Topology

```text
Tailnet
  windows-node (Tailscale on Windows)
    WSL2, mirrored networking
      anix, 172.x inside the VM
      nfsd on TCP 2049
  amac (Tailscale on macOS)
    NFS client of windows-node:/  ->  /Users/winona/src
    sshd on TCP 22
```

WSL runs in mirrored networking mode. It shares the Windows interfaces and the
Windows tailnet address. A second Tailscale client inside WSL would conflict
with the Windows client, so there is only one.

The Mac reaches the NFS export at the Windows Tailscale name, not at `anix`.
`anix` resolves only inside the WSL network. The WSL host reaches the Mac at
`amac` through MagicDNS, which Windows provides to WSL.

## Addresses

| From | To | Address | Used for |
| --- | --- | --- | --- |
| WSL | Mac | `amac` | SSH, `darwin-rebuild`, remote builds |
| Mac | WSL NFS | Windows Tailscale name or `100.x` | NFSv4.1 |
| Mac | WSL NFS | `100.x/32` source | Export and firewall scope |
| Windows | Mac | `amac` | Tailscale only |

`WINDOWS_TAILSCALE_HOST` is the Windows node name. `MAC_TAILSCALE_IP` is the
Mac's `100.x` address. Both are filled at bootstrap.

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
from `MAC_TAILSCALE_IP`.

## NFS

The WSL host exports `~/src` as the NFSv4.1 pseudo-root:

```nix
services.nfs.server.enable = true;
services.nfs.server.createMountPoints = true;
services.nfs.server.exports = ''
  /home/winona/src  MAC_TAILSCALE_IP(rw,sync,no_subtree_check,all_squash,anonuid=1000,anongid=1000,insecure,fsid=0)
'';
```

`fsid=0` makes the export the pseudo-root, so the Mac mounts `windows-node:/`.
`all_squash` maps every request to uid 1000 and gid 1000 on the WSL host.
`insecure` accepts the source port macOS uses. The export is scoped to the
Mac's single Tailscale address.

The Mac mount uses NFSv4.1 only:

```text
vers=4.1,resvport,rw,noowners,hard,intr,rsize=131072,wsize=131072,bg
```

`noowners` tells macOS to ignore the numeric owner on the wire. `hard` keeps
retrying instead of returning I/O errors. `intr` lets a signal interrupt a hung
call. `bg` retries the mount in the background when the server is not ready.

If the Mac rejects `vers=4.1`, mount with `vers=4` against the same export and
check reads and writes. Do not fall back to NFSv3; the export uses `fsid=0`.

NFSv4.1 needs only TCP 2049. There is no rpcbind, mountd, or SMB fallback.

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
installed at `/etc/nix/mac-builder` with mode `0400` on WSL. The public key is
in `winona`'s `authorizedKeys` on the Mac.

## Ports

| Port | Host | Direction | Purpose |
| --- | --- | --- | --- |
| 2049/tcp | WSL via Windows | Mac to WSL | NFSv4.1 |
| 22/tcp | Mac | WSL to Mac | SSH, `darwin-rebuild`, `ssh-ng` |
| 41641/udp | Windows, Mac | Tailscale | NAT traversal |

anix runs sshd locally to generate and hold the host key used by sops. The
firewall stays closed, and the Mac never pushes to the WSL host. No inbound SSH
is needed on WSL.

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
- The export is not scoped to the Mac: `exportfs` shows the wrong client, and
  the Mac gets `Permission denied`.
