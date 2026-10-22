# Quantification workflow

## Input and projection

The macro uses the image titles currently open in ImageJ. For raw Z/T hyperstacks it performs the selected Z projection; Average Intensity is the FV3000 method. A single-Z input is duplicated as needed. In skip-projection mode Z must equal one. Channels are split and C1/C2 are located by their channel-window prefixes. Close unrelated similarly named windows to keep selection unambiguous.

The sequence length is taken from T if T > 1, otherwise from Z if Z > 1, otherwise it is one. Confirm that the imported dimensions represent the intended experimental sequence before running.

## Initial and derived masks

The initial fluorescence mask is called `sign` in the source. It can come from an external binary sequence or from thresholding C1/C2. Manual preview reads the selected threshold limits and applies those numeric limits to the sequence. Automatic modes use the corresponding ImageJ stack threshold/mask commands.

Signal mask processing uses optional black padding followed by repeated Dilate and Erode commands, then cropping. The default intersection takes `sign AND processed sign`. The dilation and erosion counts can differ. The background mask is constructed independently as `invert(dilate(sign))`; it is not the complement of the final signal mask.

A selection is created for each frame from each mask. An optional enlargement applies to the signal ROI during measurement. The same signal selection is used for C1 and C2, and the same background selection is used for C1 and C2 within that frame.

## Arithmetic

For frame t:

```text
C1corr(t) = C1_Fluo_Mean(t) - C1_BG_Mean(t)
C2corr(t) = C2_Fluo_Mean(t) - C2_BG_Mean(t)
R(t) = C1corr(t) / C2corr(t)     [Grx1-roGFP2]
R(t) = C2corr(t) / C1corr(t)     [HyPer7]
R0 = mean(valid R values among frame positions 1 ... N)
delta(t) = (R(t) - R0) / R0
```

If a signal or background selection is empty, the macro sets the frame's intensity and ratio fields to NaN. A corrected denominator <= 0 makes the ratio NaN. The code does not reject a negative numerator on that condition alone. If the first N positions contain invalid ratios, it uses the valid ratios in those positions; it does not extend the window until N valid frames are collected. If none are valid, or their mean is zero, the baseline and normalized-change fields are NaN. If N exceeds the sequence length, N is reduced to that length.

For the frozen thesis analysis, the formal baseline remains the mean ratio of frames 1-5 for each fish. Downstream verification derives this definition from the frozen inputs. The macro's configurable behavior should be kept distinct from that fixed analysis definition.

## Results fields

| Field | Meaning |
| --- | --- |
| Frame | One-based sequence position |
| C1_Fluo_Mean | C1 mean in the signal ROI |
| C1_BG_Mean | C1 mean in the background ROI |
| C1_BG_Subtracted_Mean | C1 signal mean minus C1 background mean |
| C2_Fluo_Mean | C2 mean in the signal ROI |
| C2_BG_Mean | C2 mean in the background ROI |
| C2_BG_Subtracted_Mean | C2 signal mean minus C2 background mean |
| Ratio_C1corr_over_C2corr OR Ratio_C2corr_over_C1corr | Ratio in the selected direction |
| Ratio_First5Mean | Baseline for the selected N, despite the fixed field name |
| Ratio_Delta_over_First5Mean | Normalized change using that baseline |

Optional parameter columns are controlled by the dialog. ImageJ may include a row-index column when saving CSV. Results measurement display precision is configured as three decimals; internal calculations use measured values before display rounding. Recalculating from rounded saved means can therefore differ from an internally computed ratio.

## Analysis boundary

The macro ends with frame-level Results. Saving CSV, retaining masks/ROI records, selecting a common time window, averaging the endpoint frames for each fish, group summaries, Welch tests, and final plotting are separate steps. The thesis FV3000 endpoint window is frames 56-60; the Nikon Ti2 endpoint window is frames 22-26. Each fish supplies one endpoint value; imaging frames are repeated observations of that fish.

This source does not create a pixelwise ratio pseudocolor image or implement the separate Nikon Ti2 processing workflow.
