#=
Auto-download Racket and install Herbie on first use.

Storage: all files go into `joinpath(first(DEPOT_PATH), "herbie_macros")/`.
=#

import Downloads

const RACKET_VERSION = Ref("9.1")

# --- Paths ---

function _depot_dir()
    joinpath(first(Base.DEPOT_PATH), "herbie_macros")
end

_racket_dir() = joinpath(_depot_dir(), "racket")
_ready_flag() = joinpath(_depot_dir(), ".herbie_ready_v1")

# --- Public API ---

"""
    ensure_herbie() -> (; racket::String, env::Dict)

Return the path to a working `racket` binary and an environment dict with
`PLTUSERHOME` pointing to the Herbie installation.  Downloads Racket and
installs Herbie automatically on first call.
"""
function ensure_herbie()
    depot = _depot_dir()
    if isfile(_ready_flag())
        return _herbie_cmd(depot)
    end

    mkpath(depot)
    racket, raco = _find_or_install_racket(depot)
    _install_herbie_pkg(raco, depot)
    touch(_ready_flag())
    @info "Herbie is ready!"
    return _herbie_cmd(depot)
end

function _herbie_cmd(depot)
    racket_dir = _racket_dir()
    racket = if isfile(joinpath(racket_dir, "bin", "racket"))
        joinpath(racket_dir, "bin", "racket")
    else
        r = Sys.which("racket")
        r === nothing && error("Racket not found — delete $depot and retry")
        r
    end
    env = copy(ENV)
    env["PLTUSERHOME"] = depot
    return (; racket, env)
end

# --- Find or install Racket ---

function _find_or_install_racket(depot)
    # 1. Cached installation
    rd = _racket_dir()
    rb = joinpath(rd, "bin", "racket")
    rc = joinpath(rd, "bin", "raco")
    if isfile(rb) && isfile(rc)
        return rb, rc
    end

    # 2. System Racket
    sys_racket = Sys.which("racket")
    sys_raco   = Sys.which("raco")
    if sys_racket !== nothing && sys_raco !== nothing
        @info "Using system Racket" path = sys_racket
        return sys_racket, sys_raco
    end

    # 3. Download
    _install_racket()
    isfile(rb) || error("Racket installation failed — $rb not found")
    isfile(rc) || error("Racket installation failed — $rc not found")
    return rb, rc
end

# --- Candidate download URLs (tried in order) ---

function _racket_urls()
    v = RACKET_VERSION[]
    arch = Sys.ARCH === :x86_64 ? "x86_64" :
           Sys.ARCH === :aarch64 ? "aarch64" :
           error("Unsupported architecture: $(Sys.ARCH)")
    base = "https://mirror.racket-lang.org/installers/$v"

    if Sys.islinux()
        return [
            "$base/racket-minimal-$v-$arch-linux-cs.sh",
            "$base/racket-minimal-$v-$arch-linux-buster-cs.sh",
            "$base/racket-$v-$arch-linux-cs.sh",
            "$base/racket-$v-$arch-linux-buster-cs.sh",
        ]
    elseif Sys.isapple()
        return [
            "$base/racket-minimal-$v-$arch-macosx-cs.dmg",
            "$base/racket-$v-$arch-macosx-cs.dmg",
        ]
    else
        error("Unsupported OS.  Install Racket manually: https://racket-lang.org/download/")
    end
end

function _download_first(urls, dest)
    for url in urls
        try
            @info "Trying $url"
            Downloads.download(url, dest)
            return url
        catch
            continue
        end
    end
    error(
        "Could not download Racket.  Tried:\n" *
        join(("  • $u" for u in urls), "\n") *
        "\nInstall Racket manually: https://racket-lang.org/download/"
    )
end

# --- Platform-specific Racket installers ---

function _install_racket()
    if Sys.islinux()
        _install_racket_linux()
    elseif Sys.isapple()
        _install_racket_macos()
    else
        error("Auto-install not supported on this OS.  Install Racket manually.")
    end
end

function _install_racket_linux()
    depot = _depot_dir()
    installer = joinpath(depot, "racket-installer.sh")
    _download_first(_racket_urls(), installer)
    chmod(installer, 0o755)

    rd = _racket_dir()
    mkpath(rd)
    target = joinpath(rd, "installer.sh")
    cp(installer, target; force = true)

    @info "Installing Racket…"
    run(Cmd(`sh $target --in-place`; dir = rd))

    rm(installer; force = true)
    rm(target; force = true)
    @info "Racket installed" path = rd
end

function _install_racket_macos()
    depot = _depot_dir()
    dmg = joinpath(depot, "racket.dmg")
    _download_first(_racket_urls(), dmg)

    mount = mktempdir()
    @info "Mounting disk image…"
    try
        run(`hdiutil attach $dmg -mountpoint $mount -nobrowse -quiet`)

        # The DMG contains a single top-level directory, e.g. "Racket v9.1"
        entries = readdir(mount)
        idx = findfirst(e -> startswith(lowercase(e), "racket"), entries)
        idx === nothing && error("Cannot find Racket in DMG.  Contents: $entries")
        src = joinpath(mount, entries[idx])

        rd = _racket_dir()
        isdir(rd) && rm(rd; recursive = true)
        @info "Copying Racket…"
        run(`cp -R $src $rd`)   # preserves symlinks & permissions

        @info "Racket installed" path = rd
    finally
        try run(`hdiutil detach $mount -quiet`) catch end
        rm(dmg; force = true)
    end
end

# --- Install Herbie Racket package ---

function _install_herbie_pkg(raco, depot)
    @info "Installing Herbie (this may take several minutes)…"
    env = copy(ENV)
    env["PLTUSERHOME"] = depot
    try
        run(setenv(`$raco pkg install --auto herbie`, env))
    catch e
        error(
            "Failed to install Herbie.\n" *
            "This typically requires Rust — install it from https://rustup.rs/\n" *
            "Then delete $depot and try again.\n" *
            "Original error: $e"
        )
    end
    @info "Herbie installed."
end
