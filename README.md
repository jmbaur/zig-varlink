<!--
SPDX-FileCopyrightText: 2023 Väinö Mäkelä <vaino.makela@iki.fi>

SPDX-License-Identifier: Apache-2.0 OR MIT
-->

# zig-varlink

[![builds.sr.ht status](https://builds.sr.ht/~mainiomano/zig-varlink/commits/main.svg)](https://builds.sr.ht/~mainiomano/zig-varlink/commits/main?)

zig-varlink is a WIP [Varlink] library for Zig. Design goals:

- Let the user manage their own sockets as much as possible, or don't require
  the usage of sockets in the first place
- Don't depend on nonportable operating-system features
- Use code generation and/or Zig's comptime capabilities to make Varlink
  interfaces easy to use and implement

## License

zig-varlink follows version 3.0 of the [REUSE Specification]. The library as a
whole is licensed under Apache-2.0 or MIT, at your option, but please see the
individual files for their copyright information.

[Varlink]: https://varlink.org/
[REUSE Specification]: https://reuse.software/spec/
