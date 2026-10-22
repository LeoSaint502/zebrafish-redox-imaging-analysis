# Zebrafish redox imaging analysis

This repository preserves the integrated Fiji/ImageJ macro used for ROI-based quantification of Grx1-roGFP2 and HyPer7 time-series images acquired with an FV3000 microscope. The macro performs Z projection, channel splitting, frame-specific signal and background mask construction, mean-intensity measurements, background subtraction, excitation-ratio calculation, and baseline normalization.

## Code version

The source file is `macros/Full_ZPROJ_RealSignIntersect_BG_Ratio_macro_v12.ijm`. The archived filename identifies the integrated v12 source; the file is distributed byte for byte. Its SHA-256 is `9a77ab2db374477879f94e8968f1bf0331146bab547ade0d40f09938e6634f9d`. A Git commit permalink identifies the public snapshot. Checksums of the public content files are recorded in `SHA256SUMS`.

## Environment and input

Run the `.ijm` file in Fiji/ImageJ using **Plugins > Macros > Run**. The exact Fiji/ImageJ version used for the experimental runs was not recorded in the available archive. The macro uses ImageJ macro language and standard stack, threshold, binary morphology, Results, and ROI Manager commands; it does not explicitly invoke a third-party analysis plugin.

Open the image in Fiji before running the macro. Use an importer appropriate to the source format, preserving channels, Z slices, time points, bit depth, and calibration. The macro selects an already-open image; it does not implement file-format import. Inputs may be a multichannel Z/T hyperstack or an already Z-projected sequence with Z = 1. The macro requires at least two channels. For the FV3000 workflow, use **Average Intensity** Z projection at each time point.

## Channels and ratios

| FV3000 experiment | C1 excitation | C2 excitation | Select ratio direction |
| --- | --- | --- | --- |
| Grx1-roGFP2 | 405 nm | 488 nm | C1/C2 |
| HyPer7 | 405 nm | 488 nm | C2/C1 |

These channel identities follow the acquisition settings. The macro works with C1/C2 indices and does not infer wavelength or probe identity from the image. Both channels were acquired with Sequential Scan set to Line.

For each frame and channel, the macro computes `Icorr = mean(signal ROI) - mean(background ROI)`. It then computes `R = C1corr/C2corr` or `R = C2corr/C1corr`, according to the selected direction. The signal ROI and background ROI for a frame are each used on both channels. These are ratios of ROI means.

## Masks and baseline

The initial fluorescence mask can be generated from projected C1 or C2, or supplied as an open 8-bit single-channel binary sequence. Manual thresholding can be set numerically or adjusted on a preview frame; the selected limits are reused across the sequence. Automatic threshold methods are also available.

The signal branch optionally adds black padding, applies dilation and erosion, crops to the original dimensions, and intersects the result with the initial fluorescence mask. The background branch starts independently from the initial fluorescence mask, dilates it, and inverts it. ROI selection follows the masks frame by frame.

The default baseline length is five frames. The code averages valid ratios within the first N frame positions, then outputs `(R - R0)/R0`. The output name `Ratio_First5Mean` is retained even when N is changed. See [workflow](docs/workflow.md) for the precise invalid-frame behavior and [parameters](docs/parameters.md) for defaults and required run records.

## Running and saving results

1. Save any existing Results table and ROI Manager entries before starting. The macro resets ROI Manager and can clear Results.
2. Open the image, check C/Z/T dimensions and channel identity, and close unrelated channel windows.
3. Run the macro and choose the input type, Z projection, mask source, threshold and morphology settings, ratio direction, and baseline length. Inspect the offered previews.
4. Enable **Output selected parameters to Results** when retaining a run record. Record Fiji/ImageJ version and Binary Options separately.
5. Inspect Results and save it as CSV using the Results window. The macro populates Results; it does not automatically write a CSV or save masks. Preserve any needed mask/ROI images separately.

## Output and downstream analysis

Results includes frame index, signal and background means for both channels, their background-subtracted values, the selected ratio, baseline mean, and normalized ratio change. Optional columns record selected parameters. The field names are listed in [workflow](docs/workflow.md).

For the thesis analysis, frozen FV3000 CSV intensity fields were subsequently used to verify the ratio direction and consistently derive the per-fish first-five-frame baseline and normalized sequence. The downstream workflow selected a common analysis window, averaged the last five frames for each fish, performed a two-sided unpaired Welch t-test on fish endpoints, and generated plots. Endpoint descriptions use SD; time-series group bands use SEM. The macro itself does not perform these group statistics or final plotting.

Nikon Ti2 experiments used a separate workflow with drift-corrected fixed muscle/background ROIs and Excel formula chains. This macro is documented here for the FV3000 experiments. Experimental images, measurements, and downstream analysis files are outside this repository's content.

## Known limitations and run records

Threshold and morphology settings affect spatial selection. The source defaults document the interface and do not establish which values were selected in every historical run. Record the actual settings for each new run. Binary morphology also depends on ImageJ Binary Options, which the macro does not fully initialize.

The macro checks key mask properties and sequence length. An external mask must additionally match image geometry and spatial registration. Empty masks and nonpositive ratio denominators produce NaN results. A negative corrected numerator can produce a negative ratio. The first-N-position baseline behavior, Results precision, and persistence of intermediate windows are described in the workflow document.

The macro calculates fluorescence-ratio changes. Biological interpretation depends on the probe and experiment: Grx1-roGFP2 reports glutathione-related relative redox changes, whereas HyPer7 reports an H2O2-related response.
