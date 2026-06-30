# zerkal

Floating Wayland overlay that draws an animated planet at the centre of the
screen with the covers of your recently played tracks orbiting it. Click a
cover to jump to that track in Spotify.

![preview](preview.jpg)

Built on [quickshell](https://quickshell.outfoxxed.me/), tested on Hyprland.

## How it works

- The accent colour of the planet, the dashed orbit ring, and every cover
  is read live from `/tmp/lyrics.json`.
- That JSON is produced by the [`lyrics`](https://github.com/Rise-zen/lyrics)
  daemon (`lyrics --json`), which watches MPRIS, downloads cover art, and
  picks a vibrant accent from each cover.
- `qml/shell.qml` polls the file every 250 ms and feeds the overlay built as
  a `WlrLayershell` Overlay layer.

## Install

### Nix (no clone, no PATH wrangling)

```sh
# try it once, runtime deps come along automatically
nix run github:zerkal-beta/zerkal             # orbital
nix run github:zerkal-beta/zerkal#galaxy      # galaxy mode

# permanent install into your profile
nix profile install github:zerkal-beta/zerkal
zerkal toggle
```

For local hacking the flake also exposes a dev shell with quickshell,
playerctl, ImageMagick and watchexec:

```sh
git clone https://github.com/zerkal-beta/zerkal && cd zerkal
nix develop           # or `direnv allow` if you have direnv
```

### Arch / paru

```sh
git clone https://github.com/zerkal-beta/zerkal.git ~/Projects/zerkal
chmod +x ~/Projects/zerkal/zerkal.sh
paru -S quickshell-git playerctl jq qt6-multimedia
```

Plus the `lyrics` daemon for live data — see
<https://github.com/Rise-zen/lyrics>.

## Run

```sh
# kick off the lyrics daemon once (in autostart, tmux, etc.)
lyrics --json &

# show / hide the zerkal overlay
~/Projects/zerkal/zerkal.sh toggle
```

Bind it to a key in Hyprland (`~/.config/hypr/keybindings.conf`):

```ini
bind = SUPER, O, exec, ~/Projects/zerkal/zerkal.sh toggle
```

And add to autostart so it's always ready (zero-cost when hidden):

```ini
exec-once = lyrics --json
exec-once = ~/Projects/zerkal/zerkal.sh start
```

## Interaction

- **Left click on backdrop / Esc** — close
- **Left click on a cover** — `playerctl --player=spotify open <uri>` jumps
  to that track in Spotify
- **Mouse wheel** — nudge the orbit one slot per tick (the auto-rotation
  keeps drifting underneath)

## Customising the centerpiece

`qml/center.png` is the still emblem in the middle. Replace the PNG with
any transparent-background image — quickshell hot-reloads on save.

## License

MIT — see [LICENSE](LICENSE).
