# Dynamic Ship BOL Commodity Lines and Pro Barcode

![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg) ![Business Central 25+](https://img.shields.io/badge/Business%20Central-25%2B-0B7E8A) ![AL](https://img.shields.io/badge/language-AL-5C2D91)

**For Insight Works Dynamic Ship: print what is actually on each pallet, the NMFC and freight class, and the pro number as a barcode on your Bill of Lading.**

<!-- DEMO: record a 30-60 second screen capture, save it as docs/images/demo.gif, then replace this comment with:
![Demo](docs/images/demo.gif) -->

## What it does

Extends the **DSHIP Bill of Lading** report dataset with:

| Column | What it holds |
|---|---|
| `MID_ShipProNumber` | The pro number entered on the sales order, found from a sales order, warehouse shipment or posted shipment |
| `MID_ShipProNumberBarcode` | The same pro number as a Code 39 barcode image |
| `MID_perCommDescription` | One line per item on the license plates in that commodity group, in a format you choose |
| `MID_perCommNMFC` | NMFC from the license plate's freight options |
| `MID_perCommFreightClass` | Freight class from the license plate's freight options |

License plates are matched to each commodity line exactly when possible, with progressively looser rules only when needed. Freight options are read late-bound, so the **Dynamic Ship: Freight Options** app is optional.

## Setup

1. Open **BOL Commodity Setup** and set the **Commodity Line Format**. Placeholders: `%1` quantity, `%2` item no., `%3` item no. 2, `%4` description, `%5` base unit of measure. The default is `Qty: %1 %2 - %4`.
2. **Add the columns to your layout.** No layout is included, because the Dynamic Ship layouts belong to Insight Works. On **Report Layouts**, export the Bill of Lading layout you use, add the `MID_*` fields where you want them, and import it as a new layout.
3. Assign `MID BOL SETUP` to the admin who maintains the format. Everyone with `D365 BASIC` can print.

## Install

**From a release (no build tools needed)**
1. Download the `.app` file from the latest [release](../../releases).
2. In Business Central, open **Extension Management** → **Manage** → **Upload Extension** and select the file.
3. Assign the permission set listed below to the people who use it.

**From source**
1. Clone this repo and open `DynamicShip-BOLCommodity` in VS Code with the [AL Language extension](https://marketplace.visualstudio.com/items?itemName=ms-dynamics-smb.al).
2. Put your sandbox name and tenant ID in `.vscode/launch.json`, then run **AL: Download Symbols**.
3. Press **F5** to publish to your sandbox.

Always test in a sandbox before you install in production.

## Technical details

| | |
|---|---|
| Object ID range | 50230–50249 |
| Object prefix | `MID` |
| Dependencies | Insight Works Dynamic Ship: Integrated Shipping, IWorks Common |
| Permission set(s) | `MID BOL SETUP` (admin); `D365 BASIC` is extended automatically |
| Business Central | Online, version 25 or later |

## Need help with this app?

[Midstream Integrations](https://www.MidstreamIntegrations.com) installs, adapts and supports these extensions, and builds new ones for your process.
**[Book a 20-minute call](https://midstreamintegrations.com/contact)** · intro@MidstreamIntegrations.com

## Contributing

Issues and pull requests are welcome; see [CONTRIBUTING](https://github.com/Midstream-Integrations/.github/blob/main/CONTRIBUTING.md).
Found a security problem? Please follow the [security policy](https://github.com/Midstream-Integrations/.github/blob/main/SECURITY.md) instead of opening a public issue.

## License

[MIT](LICENSE) © Midstream Integrations
