# Contributing to EnManga

Thanks for wanting to help! EnManga is a small hobby project, so keep things simple.

## Reporting bugs

Use [New issue → Bug report](../../issues/new/choose). The most useful things to include are:
- your console (Vita 1000, 2000 or PS TV) and firmware,
- what you did and what went wrong,
- the name and folder layout of the manga involved,
- `ux0:data/enmanga/log.txt`, if the app wrote one.

Please don't upload copyrighted manga to issues.

## Suggesting features

Use [New issue → Feature idea](../../issues/new/choose). Say what you'd like and why. A comparable feature in another reader helps.

## Code

- The app is plain Lua in `app/`, running on NOBORU's lpp-vita runtime (`app/eboot.bin`). There's nothing to compile: `python3 tools/build_vpk.py` zips `app/` into a VPK.
- Keep everything **offline and local**: EnManga doesn't access the network and won't add online sources.
- New user-visible features should come with an update to the matching page in `docs/` and a line in `CHANGELOG.md`.
- Test on real hardware if you can, and say which model you used in the pull request.
- Large changes: please open an issue first so we can talk about it.

## AI-assisted contributions

EnManga itself was largely written with an AI assistant (see the README). AI-assisted pull requests are fine. Please say so in the PR, and make sure you've actually run the change on a Vita.

## License

By contributing you agree that your contribution is released under the project's license, the [GNU GPL v3.0](LICENSE).
