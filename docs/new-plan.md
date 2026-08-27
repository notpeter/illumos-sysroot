# Plan: Reproduce the illumos sysroot releases deterministically (CI + local-VM validation)

**Repo:** `notpeter/illumos-sysroot` (branch `2026_updates`)
**Audience:** a CLI coding agent with access to local **OmniOS** VMs for builds, validation, and test runs.
**Goal:** Deterministically **re-create all three defined sysroot releases** from pinned public inputs, in a way that (a) is byte-reproducible across re-runs and machines, and (b) can be independently re-verified. Every release must contain **vanilla illumos** bits (not `stlouis`/distro-forked).

**Target releases (all three):**
1. `20181213-de6af22ae73b-v2`
2. `20210501-e0b4275f34-v0`
3. `20231226-ae676b1204fb-v1`

All three already have complete `profiles/<DATE>.mk` and `env/illumos.<DATE>.sh` files in the repo — the per-release parameters are done; this plan is about driving them through a reproducible build+validate pipeline.

---

## 0. Orientation (read before touching anything)

The sysroot ships headers (text) plus a substantially **binary** payload: core shared libraries (`.so`), the C runtime objects (`crt1.o`, `crti.o`, `crtn.o`, `values-*.o`), and one static archive (`libssp_ns.a`). It is assembled by `mf2tar` (Rust) reading an IPS repo (`repo.redist`) and emitting a normalized tarball, plus four generated shim libraries (32/64-bit `libgcc_s.so.1` and `libssp.so.0.0.0`).

Two reproducibility layers exist and prove different things:

1. **Packaging determinism** — the tar/gzip envelope is byte-identical given identical input files. **Already handled** by `mf2tar` (single `SOURCE_DATE_EPOCH` mtime, uid/gid 0, fixed modes, ustar, deterministic entry order) and `gzip -n`.
2. **Binary determinism** — the `.so`/`.o`/`.a` payload bytes are themselves reproducible. This is downstream of the **illumos-gate build**, and is the harder, in-scope work here.

**Core architectural principle:** the *flavor* of the payload (vanilla vs. `stlouis`) is decided by the **source tree you compile**, not by the build host or where the toolchain comes from. Each release therefore builds from its **pinned illumos-gate commit** on the release's `sysroot/<DATE>` backport branch — never by installing a distro's prebuilt `system/*` packages.

**Existing reproducibility tooling in the repo — use it, don't reinvent:**
- `scripts/check-repo-redist-repro.sh` — builds illumos-gate **twice** and compares **normalized `repo.redist` fingerprints** (this is the double-build check; run it on an OmniOS builder).
- `scripts/fingerprint-repo-redist.sh` — writes normalized fingerprints for a `repo.redist` tree.
- `scripts/build-omnios-sysroot.sh` — the full gate-build + assemble path.
- `scripts/assemble-sysroot-from-repo.sh` — assembles a sysroot tar from an existing `repo.redist` (+ prebuilt shims) on any host.
- `scripts/receive-installed-packages.sh` — receive packages into a local repo (smoke path).
- `scripts/extract-prebuilt-shims.sh`, `scripts/liblinks.sh` — shim seeding and library-symlink checks.

---

## 1. Locked decisions (implement; do not re-litigate)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Do all three releases** (20181213-v2, 20210501-v0, 20231226-v1). | Maintainer directive. |
| D2 | **Build each payload from its pinned stock gate** (`sysroot/<DATE>` branch @ pinned commit). Never install distro `system/*` packages. | Guarantees vanilla/distro-neutral bits. |
| D3 | **Host stays OmniOS** (local VMs now; `vmactions/omnios-vm` in CI). No `helios-vm`. Build old gate on a modern OmniOS host **via the `sysroot/<DATE>` backport branches** (that's what they're for). | Host is only a toolchain provider. |
| D4 | Use the **stock closed-bins** tarball, not the host's `/opt/onbld/closed`; checksum + archive it. | The one place a distro-specific artifact could leak in. |
| D5 | **Use each profile's existing `SOURCE_DATE_EPOCH`** (already set to the release's gate-commit date). Do not change these. | They define the canonical, reproducible mtime per release. |
| D6 | **Drop Rust** from every release's toolchain. | Verified: gate has **zero** Rust (0 `.rs`, 0 `Cargo.toml`, none in `Makefile.master`) on current tip and in these older commits. Rust is a distro/`stlouis` concern only. |
| D7 | **Ship with Java** now — install the JDK each release's env requires. | Maintainer directive (D-Java). Full `nightly` compiles `poold` + DTrace Java API. See the matrix for per-release Java version. |
| D8 | **Use each release's env-specified primary compiler** (see matrix). Shadow compiler is optional: it only produces diagnostics and does **not** affect primary build output, so it can be disabled (`SHADOW_CCS=`) to shrink the toolchain **without** changing the payload. Keep the env as-is if unsure. | Faithful reproduction needs the correct *primary* compiler; shadow is free to drop. |
| D9 | **No `ar` fix required.** | illumos `ar` is nondeterministic (no `-D`, no `SOURCE_DATE_EPOCH`; members take `st_mtime`/uid/gid, symtab stamped `time(0)`), **but** the only payload `.a` is `libssp_ns.a`, a **copy-in from the pinned GCC**, not archived by our build. crt objects use `PROCESS_COMMENT` + `STRIP -x`. Pin gcc → stable. (Verify — V3.) |
| D10 | **Payload package set (all releases):** `system/header`, `system/library`, `system/library/math`, `system/library/c-runtime`, `system/library/security/gss`. Already in every profile. No `libtecla`. | Minimal; covers all core + Rust link needs; gss retained per consumer requirement. |
| D11 | **Toolchain durability = `toolchain.lock`** (URL+hash + validating cache), **per release**. Do not depend on the OmniOS live repo. | Maintainer directive (D-lock). Reproducibility must not depend on anyone's retention policy. |
| D12 | **No zone** for CI builds (the VM is already the isolation boundary). | Avoid zone-in-VM redundancy. |
| D13 | **zlib is OUT OF SCOPE.** Do not add a zlib package; consumers needing `-lz` bring their own. | Maintainer directive (D-zlib). |
| D14 | **Scoped `lib`+`head`+`crt` build (drop Java)** is a **future, deliberately-brittle item** — not now. | Maintainer directive: ship full-nightly-with-Java today; file the scoped build as future work. |

---

## 2. Per-release build matrix (from `profiles/*.mk` + `env/*.sh`)

| Param | **20181213-v2** | **20210501-v0** | **20231226-v1** |
|---|---|---|---|
| `TARVERSION` | `20181213-de6af22ae73b-v2` | `20210501-e0b4275f34-v0` | `20231226-ae676b1204fb-v1` |
| Gate branch | `sysroot/20181213` | `sysroot/20210501` | *(direct commit)* |
| Gate commit | `de6af22ae73ba8d72672288621ff50b88f2cf5fd` | `e0b4275f346eda86b39157cd7dd3cc889a1f6988` (base `2ed5ea5a06df`, 2021-04-30) | `ae676b1204fb703d5b394f9f8d947ef6210f3c3f` |
| `SOURCE_DATE_EPOCH` | `1544726597` (2018-12-13) | `1762459338` (2025-11-06, backport tip) | `1703608857` (2023-12-26) |
| Primary compiler | gcc7-era (per env) | **gcc7** (`/usr/gcc/7`) | **gcc10** (`/opt/gcc-10` or `/usr/gcc/10`) |
| Shadow (optional/droppable) | (commented gcc7) | smatch-conditional | gcc7 or empty |
| Java | **Java 8** (`BLD_JAVA_8`) | Java 8/default | **Java 11** (`BLD_JAVA_11`) |
| `LIBGCC_VERSION` | `4_8_0` | `4_8_0` | `4_8_0` |
| Env file | `env/illumos.20181213.sh` | `env/illumos.20210501.sh` | `env/illumos.20231226.sh` |
| Orig build host | OmniOS r151030+ | OmniOS r151038 | OmniOS r151046 |

**Notes:**
- `20231226` has **no** `sysroot/<DATE>` backport branch — it builds stock gate directly at its commit (buildable on r151046). On a *newer* host it may need a backport branch created; flag if the local VM is newer than r151046.
- `20210501-v0` is a **prerelease** produced from the 2021 base via a Nov-2025 build backport — its `SOURCE_DATE_EPOCH` is the backport commit date by design. Likely no prior published artifact to match (produce reproducibly).
- `20181213-v2` is an **existing published** release — attempt to match the published `.tar.gz` hash and characterize any diff (V2b).
- Toolchain differs per release: **gcc7 + JDK8** for 2018/2021, **gcc10 + JDK11** for 2023. `toolchain.lock` is therefore per-release (or a 3-way matrix).

---

## 3. Toolchain (minimal, pinned per release)

**Per-release toolchain set (full-nightly mode, Java kept):**
- 20181213 / 20210501: `gcc7`, `developer/build/onbld`, `developer/build/gnu-make`, **JDK 8** (+ base deps: perl, etc.).
- 20231226: `gcc10`, `onbld`, `gnu-make`, **JDK 11** (+ base deps).
- All: **no Rust**, shadow droppable, `git` need not be in the VM if checkout happens on the runner and syncs in.

**Durability = `toolchain.lock` (D11).** IPS is content-addressed: files live at `<repo>/file/1/<sha1>`, `chash` = SHA-1 of the compressed blob, the file-action key = SHA-1 of the uncompressed content, and modern packages carry `pkg.content-hash=gzip:sha512t_256:…`.
- Generate a **per-release** `toolchain.lock` (pinned FMRIs + per-file hashes) for the exact compiler/JDK/onbld/gnu-make versions each release needs.
- Implement fetch → verify (`chash` on download; file-hash / `content-hash` after decompress) → cache; assemble a local repo to install from. `pkgrecv -s <repo> -d ./localrepo <fmris>` does hash-verified fetch-into-a-local-repo; cache `./localrepo` between runs (key on the lock hash).
- **Durable source:** the OmniOS release the profile names, or **Helios** (`pkg.oxide.computer/helios/2/dev`, publisher `helios-dev`) which is r151046-based and retains deep history so its content-addressed URLs persist. **Only** pull *toolchain* packages this way — never Helios `system/*` payload packages (that would inject `stlouis` bits). For the gcc7/JDK8 era (2018/2021), verify the durable source still carries those versions; if not, fall back to archiving them yourself as a one-time `.p5p` stored in a Release asset.

For **local OmniOS VM** runs the live repo is acceptable while iterating; the lock/cache is required for CI longevity and independent reproducibility.

---

## 4. Implementation phases

### Phase 1 — Pipeline plumbing (shared)
- [ ] Confirm `SOURCE_DATE_EPOCH` from each `profiles/<DATE>.mk` flows through `mf2tar` (it reads the env var). Do not override the profile values (D5).
- [ ] Ensure each build checks out the correct `sysroot/<DATE>` branch @ pinned commit and uses **stock closed-bins**, checksum-recorded (D2, D4).
- [ ] Remove Rust from all toolchain install lists (D6). Add a **guard** step that fails if the pinned gate tree contains `*.rs`/`Cargo.toml` (V5).

### Phase 2 — Per-release toolchain locks (D11)
- [ ] Produce `toolchain.<DATE>.lock` for each release (correct gcc + JDK era per matrix). Implement fetch-verify-cache and clean install into a fresh OmniOS VM from the lock (not the live repo).
- [ ] Confirm gcc7/JDK8 availability from the chosen durable source for 2018/2021; archive to `.p5p` fallback if missing.

### Phase 3 — Build + assemble each release (full nightly, Java kept — D7)
For each of the three profiles:
- [ ] Run the gate build (`scripts/build-omnios-sysroot.sh -r <DATE> …`) in an OmniOS VM to produce `repo.redist`.
- [ ] Assemble with `mf2tar` from `repo.redist` using the profile's package set (D10) + existing `EXCLUDE_DIRS`; extract the **non-debug (`-nd`)** variant consistently.
- [ ] Build shims with the release's **pinned primary gcc** (matrix) so `.comment` matches the payload; shims already strip with `-s`.
- [ ] Emit `output/illumos-sysroot-i386-<TARVERSION>.tar.gz` + `.sha256`.

### Phase 4 — Reproducibility hardening (per release)
- [ ] Run V1–V3, V6, V7. Fix nondeterminism (suspects: embedded build path/date in crt objects — confirm `PROCESS_COMMENT`/strip ran; `libssp_ns.a` copy-in stability tied to the pinned gcc).
- [ ] For each release record the full input set (gate commit, closed-bins checksum, `toolchain.<DATE>.lock`, `SOURCE_DATE_EPOCH`) in release notes so a third party can reproduce.

### Phase 5 (future, deferred — D14)
- [ ] Scoped `bldenv` build of `usr/src/lib` + `usr/src/head` + crt, **skipping `usr/src/cmd`**, to drop the JDK. Deliberately brittle; file as a follow-up, not part of this pass.

---

## 5. Validation plan (use the local OmniOS VMs)

> Reproducibility only counts if someone verifies. These are gating acceptance criteria, **run per release**.

- [ ] **V1 — Double-build (same machine).** Use `scripts/check-repo-redist-repro.sh` to build gate twice and compare normalized `repo.redist` fingerprints; then assemble twice and assert identical `.tar.gz` **and** identical uncompressed tar. Any diff → investigate.
- [ ] **V2 — Independent rebuild (second clean VM).** Repeat on a **separate, clean** OmniOS VM; assert the same top-level hash. Headline guarantee. *(Confirm the environment can spin up a second clean VM — this is the check that earns the claim.)*
- [ ] **V2b — Match published artifact (20181213-v2 only).** Diff the rebuild against the published `.tar.gz`; if it differs, characterize whether the diff is envelope-only (tar/gzip metadata) or payload, and decide whether to adopt a canonical deterministic baseline going forward.
- [ ] **V3 — `libssp_ns.a` / crt stability.** Extract `libssp_ns.a` (both arches) + crt objects from two builds; assert byte-identical. If `libssp_ns.a` differs, the pinned gcc isn't actually pinned — fix the lock.
- [ ] **V4 — Cross-link + run smoke test.** Cross-compile a small C program (libc, libm, libsocket, libpthread) against the sysroot via `--sysroot`, then **run it in an OmniOS VM**. Proves usability, not just reproducibility. Use the era-appropriate VM where feasible.
- [ ] **V5 — Rust-absence guard.** CI step asserting the pinned gate has no `*.rs`/`Cargo.toml` (D6).
- [ ] **V6 — Neutrality check.** Confirm no `stlouis` content: payload came from stock `sysroot/<DATE>` gate (by construction); spot-check sonames/versions match stock-gate expectations. Never source `system/*` from Helios.
- [ ] **V7 — Package-set completeness.** Assert the tar contains `usr/include`, `usr/lib/{,amd64/}lib*.so*`, crt objects, `libgcc_s`/`libssp` shims, `libgss`, and **excludes** `usr/bin`, `etc`, `var`, `usr/share`, `usr/sbin`, `usr/ccs`, `bin`, `sbin` (mirror the existing CI `grep`/`! grep` assertions). Use `scripts/liblinks.sh` for symlink sanity.

**Optional, non-blocking:** cross-distro link checks on OpenIndiana (`vmactions/openindiana-vm`) and manual legs on Helios/SmartOS. Deferred.

---

## 6. Out of scope / known gaps (record; don't silently assume)

- **zlib (`libz`)** — **out of scope (D13).** Not in base gate library packages; consumers needing `-lz` bring their own.
- **OpenSSL (`libssl`/`libcrypto`)** — not in gate at all. TLS software supplies its own crypto.
- **C++ runtime (`libstdc++`)** — from GCC, not gate. If C++ cross-compilation is ever needed, copy-in/shim `libstdc++.so` from the pinned gcc (mirroring `libgcc_s`/`libssp`). Not now.
- **Full gate byte-reproducibility** — this plan makes the *sysroot payload* reproducible, not the entire gate.
- **Scoped no-Java build** — deferred (D14).

---

## 7. Open questions for the maintainer

1. **gcc7 / JDK8 durable source:** confirm the chosen durable repo still carries the exact gcc7 + JDK8 versions the 2018/2021 env files expect; if not, approve archiving them to a `.p5p` fallback.
2. **20181213-v2 hash target:** is matching the *published* artifact byte-for-byte a requirement, or is a canonical deterministic rebuild acceptable if only envelope metadata differs? (Affects V2b.)
3. **Newer-than-r151046 local VM:** if the VM used for `20231226` is newer than r151046, do we create a `sysroot/20231226` backport branch, or pin the builder VM to r151046?

---

## 8. Reference: verified findings (so the agent needn't re-derive)

- **Rust:** 0 `.rs`, 0 `Cargo.toml`, 0 `rustc`/`cargo` in `usr/src/Makefile.master` on current gate tip; older pinned commits predate any gate Rust. Kernel is C/asm. → not required.
- **Java:** ~197 `.java` in gate; `Makefile.master` wires `JAVAC`/`JAVADOC`/`JAR`; consumers are `usr/src/cmd/pools/poold` + DTrace Java API. Full nightly needs a JDK (era per matrix).
- **`ar`:** `usr/src/cmd/sgs/ar` — no `-D`; no `SOURCE_DATE_EPOCH`; members take `st_mtime`/uid/gid, symtab stamped `time(0)`. Nondeterministic, but **not in the payload path** (only `.a` is the gcc copy-in `libssp_ns.a`).
- **crt build:** `usr/src/lib/crt/Makefile.com` builds `crt{1,i,n}.o` + `values-*.o` with `POST_PROCESS_O = $(PROCESS_COMMENT) $@ ; $(STRIP) -x $@`. No `libssp_ns.a` built here (no libssp source in gate → copy-in from GCC).
- **IPS timestamps:** file actions carry **no** `timestamp=` (0/2365 in `system/library`, 0/40 in `c-runtime`). Identity is the content hash; mtime assigned at install → clobbering to `SOURCE_DATE_EPOCH` is correct and lossless.
- **`system/library` coverage:** 118 lib stems incl. `libc`, `libsocket`, `libnsl`, `libresolv`, `libposix4`/`librt`, `libsendfile`, `libpthread`, `libdl`, `libumem`, `libnvpair`, `libkstat`, `libscf`, `libsec`, `libelf`, `libproc`. Rust `x86_64-unknown-illumos` default links (`-lsocket -lposix4 -lpthread`) fully covered.
- **Repro tooling already present:** `scripts/check-repo-redist-repro.sh` (double-build compare), `scripts/fingerprint-repo-redist.sh` (normalized fingerprints), `scripts/liblinks.sh` (symlink checks).
- **Helios repo (toolchain durability source only):** `pkg.oxide.computer/helios/2/dev`, publisher `helios-dev`; deep version retention; content-addressed files at `file/1/<sha1>`.
