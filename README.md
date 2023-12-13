<!--
SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>

SPDX-License-Identifier: Apache-2.0 OR MIT
-->

# zig-varlink

[![builds.sr.ht status](https://builds.sr.ht/~mainiomano/zig-varlink/commits/main.svg)](https://builds.sr.ht/~mainiomano/zig-varlink/commits/main?)

zig-varlink is a [Varlink] library for Zig. Features:

- Bring your own sockets. zig-varlink only implements Varlink and lets you use
  whatever transports and polling systems you like.
- Use of code generation and Zig's comptime capabilities to make Varlink
  interfaces easy to use and implement

See [our Varlink certification implementation][certification] for an example on usage.

## License

zig-varlink follows version 3.0 of the [REUSE Specification]. The library is
licensed under Apache-2.0 or MIT, at your option, but please see the individual
files for their copyright information.

[Varlink]: https://varlink.org/
[certification]: test/certification/
[REUSE Specification]: https://reuse.software/spec/
