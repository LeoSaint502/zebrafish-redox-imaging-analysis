# Parameters and run records

The table records defaults read directly from the integrated source. These are interface defaults; individual historical runs may have used other selections. Save actual settings with each new run.

| Parameter | Source default / options |
| --- | --- |
| Input image type | Raw Z-stack/hyperstack; already projected input also supported |
| Z projection | Average Intensity; Max, Min, Sum, Standard Deviation, Median also selectable |
| Mask source | C2 after projection; C1 and open external mask also selectable |
| Threshold mode | Manual adjustment on preview frame; numeric manual and four auto methods also selectable |
| Initial manual bounds | 0 and 65535; preview adjustment replaces these with selected limits |
| Preview frame | 1 |
| Process signal mask | Enabled |
| Signal dilation / erosion | 30 Dilate calls / 70 Erode calls |
| Black padding | Enabled, 100 pixels on each side before morphology, cropped afterward |
| Intersect with initial mask | Enabled |
| Signal preview / retain preview | Enabled / disabled |
| Background dilation | 50 Dilate calls, then invert |
| Background preview | Disabled; first/current frame selectable |
| Retain background mask window | Enabled |
| Signal ROI enlargement at measurement | 0 pixels |
| Ratio direction | C1/C2; set C2/C1 for HyPer7 FV3000 |
| Baseline length | 5 frame positions |
| Parameter columns in Results | Disabled |
| Clear previous Results | Enabled; ROI Manager is reset regardless of this setting |

## Recommended record for a new run

Record the Fiji/ImageJ version, importer and import settings, source image identifier, C/Z/T dimensions, spatial calibration, excitation-to-channel mapping, selected projection and mask source, threshold method and actual limits, preview frame, all morphology values, Binary Options, intersection and ROI enlargement settings, ratio direction, baseline length, and saved Results/mask/ROI filenames.

Retain the ImageJ Log together with the Results table. Intermediate channel and mask windows are not automatically archived. Review signal and background masks across frames and confirm their geometry, sequence ordering, and registration.

Morphology command counts are not physical distances. Image resolution and Binary Options affect the resulting selections. Exact historical software and per-run parameter records are not supplied with this source archive.
