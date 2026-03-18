# Pkglet Repositories
Repositories are a remote or a local path that contains several files, and in Pkglet's case, it contains [Package Manifests](/pkglet/packages).

## Example Structure
```
├── README.md     (optional)
├── com
│   ├── git-scm
│   │   └── git
│   │       └── manifest.lua
│   └── redhat
│       ├── efibootmgr
│       │   └── manifest.lua
│       └── efivar
│           └── manifest.lua
├── io
│   └── neovim
│       └── manifest.lua
└── se
    └── curl
        └── libcurl
            └── manifest.lua
```

## Adding Repositories
Adding repositories can be done by the follow process:

1. User-installed pkglet: 
```sh 
echo "main [insert repo git URL]" >> ~/.config/pkglet/repos.conf
pkglet sync
```

2. System-wide pkglet:
```sh 
echo "main [insert repo git URL]" | sudo tee /etc/pkglet/repos.conf
pkglet sync
```

## Removing Repositories
By reversing the process of adding repositories. Lmao.

## Syncing Repositories
This is useful to sync updates from the upstream URL. This is done by executing:
```sh 
pkglet sync
```

## Searching for packages
You can do that by doing:
```sh 
pkglet search [query]
```

