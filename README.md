# iw4-servers

A simple tool to parse an IW4 master server list and output to a JSON file. This will most commonly be useful for generating a favourites.json file to be used with an H2M-Mod binary that has not had its master server URL patched.

[![GNU GPLv3 licensed][gpl-badge]][gpl-url]
[![Build Status][actions-badge]][actions-url]

[gpl-badge]: https://img.shields.io/badge/License-GPLv3-blue.svg
[gpl-url]: https://github.com/amkillam/iw4-servers/blob/master/LICENSE
[actions-badge]: https://github.com/amkillam/iw4-servers/actions/workflows/ci.yml/badge.svg
[actions-url]: https://github.com/amkillam/iw4-servers/actions/workflows/ci.yml

## Usage

Usage documentation, copied directly from the output of the command `iw4-servers --help`, is provided below. Upon the outputted favourites.json file's placement in the intended game's root directory, servers listed in the file are then made available in the game's server browser, under the Favorites section.

```
iw4-servers [OPTIONS]

Options:
  -o, --output <OUTPUT>  Output file for server list [default: favourites.json]
  -g, --game <GAME>      Game to get server list for. Options: COD, H1, H2M, IW3, IW4, IW5, IW6, L4D2, SHG1, T4, T5, T6, T7 [default: H2M]
  -u, --uri <URI>        IW4 server list URI [default: https://master.iw4.zip/servers]
  -h, --help             Print help
  -V, --version          Print version  
```


