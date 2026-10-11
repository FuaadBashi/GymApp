# Body map artwork

`body_map.json` holds the front and back body outlines used by the Progress tab's muscle
map. The polygons come from **react-body-highlighter 2.0.5** (npm), copyright (c) 2020 GV79,
released under the MIT License; the licence text is in `LICENSE-react-body-highlighter.txt`.

- Source: https://github.com/giavinh79/react-body-highlighter (`src/assets/index.ts`)
- Converted by `tools/build_body_map.py`, which keeps the points unchanged (rounded to three
  decimals) and adds the mapping from each region to the app's muscles. The mapping and its
  approximations are documented at the top of that script.
