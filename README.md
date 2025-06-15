# Go-up - Go Version Updater

<p>
    <img src="https://github.com/DieTime/go-up/actions/workflows/linux.yml/badge.svg" alt="Linux support status" style="margin-right: 7px"/>
    <img src="https://github.com/DieTime/go-up/actions/workflows/macos.yml/badge.svg" alt="MacOS support status" />
</p>

## Usage

You only need to copy and run this command in the terminal.

```shell
curl -sL https://raw.githubusercontent.com/DieTime/go-up/master/go-up.sh | bash
```

You can also use wget instead of curl.

```shell
wget -qO- https://raw.githubusercontent.com/DieTime/go-up/master/go-up.sh | bash
```

## Advantages

- Supports Linux and MacOS
- Single line script usage
- Works with either curl or wget on the system
- Automatically determines the path to install a new version
- Restores the GOPATH folder if it is inside GOROOT
