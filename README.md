# card-games-asm

> Implementations of simple card games in x86_64 Linux NASM assembly

Currently, I've only implemented Crazy Eights (due to its simplicity), but Solitaire is in progress.


## Crazy Eights

**Game rules**:

* Two players, each with a hand of *7 cards* at the start
* Players take turns placing a card onto the discard pile
* Cards placed onto the discard must either have the same *suit* or *rank* as the previous top card
* Eights may be placed *at any time*. The player gets to choose which suit the eight represents
* Players may draw cards at any time during their turn
* The first player to get rid of all of their cards wins

The multiplayer functionality is implemented through **TCP sockets**. Two players may play together as long as a TCP connection can be established between them.

### Building from Source

You'll need to install `nasm`. Run `make` to compile the binary.

### QR Codes

As this implementation of Crazy Eights is less than 3 KB, it can be entirely encoded within a single **qr code**:

![binary qr code](https://raw.githubusercontent.com/grimsteel/card-games-asm/refs/heads/main/qr-crazy-eights-bin.png)

> [!NOTE]
> This QR code uses the binary encoding format, which is not supported by all QR readers

**gzipped + base64 data URI** encoded version (supported by most QR readers):

![gzipped qr code](https://raw.githubusercontent.com/grimsteel/card-games-asm/refs/heads/main/qr-crazy-eights-gz-b64.png)
