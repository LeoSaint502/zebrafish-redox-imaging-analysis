// ============================================================
// Full Workflow with selectable Z projection, optional skip-Z input, and real-sign intersection mask
//
// Original Hyperstack
// -> Selectable Z Projection or skip if already projected
// -> Split Channels
// -> Original Fluorescence Mask = sign
// -> Processed Signal Mask = sign + optional black padding + Dilate -> Erode + crop back
// -> Real Signal Mask = sign AND processed signal mask
// -> Background Mask = sign -> Dilate -> Invert
// -> Background-corrected Ratio
// -> First-N-frame Delta Ratio
//
// Version notes:
// 1. Z projection and C1/C2 are generated as intermediate windows only.
// 2. Threshold mode default = Manual: adjust on preview frame.
// 3. If "Use opened fluorescence mask stack" is selected,
//    the macro validates that the selected mask is:
//      - not the original image
//      - 8-bit
//      - single-channel
//      - same sequence length as C1/C2
// 4. Generated fluorescence masks are intermediate windows only; no mask-saving option is shown.
// 5. Input can be raw Z-stack/hyperstack or already Z-projected image.
// 6. Z projection method is selectable.
// 7. Background is generated from sign by Dilate -> Invert.
// 8. Real signal mask is generated as sign AND processed signal mask.
// 9. Results table can optionally include threshold values and key workflow parameters.
// 10. Background preview is optional and defaults to OFF for faster runs.
// ============================================================

macro "Full_ZPROJ_RealSignIntersect_BG_Ratio" {

    titles = getList("image.titles");

    if (lengthOf(titles) < 1) {
        exit("请先打开原始 hyperstack 或已经 Z projection 过的图像。");
    }

    defaultOriginal = titles[0];
    defaultMask = titles[minOf(1, lengthOf(titles)-1)];

    // -----------------------------
    // Main Dialog
    // -----------------------------
    Dialog.create("Full Z Projection + Real-sign Mask + BG-corrected Ratio Workflow");

    Dialog.addChoice("Input image:", titles, defaultOriginal);
    Dialog.addChoice(
        "Input image type:",
        newArray(
            "Raw Z-stack/hyperstack (run Z projection)",
            "Already Z-projected image (skip Z projection)"
        ),
        "Raw Z-stack/hyperstack (run Z projection)"
    );

    Dialog.addMessage("Step 1. Z-axis projection");
    Dialog.addChoice(
        "Z projection method:",
        newArray(
            "Average Intensity",
            "Max Intensity",
            "Min Intensity",
            "Sum Slices",
            "Standard Deviation",
            "Median"
        ),
        "Average Intensity"
    );
    Dialog.addMessage("If input is already Z-projected, Step 1 will be skipped.");
    Dialog.addMessage("If Z projection is run, the projected image will be generated as an intermediate window only.");

    Dialog.addMessage("Step 2. Split channels");
    Dialog.addMessage("C1/C2 images will be generated as intermediate windows only.");

    Dialog.addMessage("Step 3. Fluorescence mask source");
    Dialog.addChoice(
        "Fluorescence mask source:",
        newArray(
            "Use opened fluorescence mask stack",
            "Generate mask from C1 after Z projection",
            "Generate mask from C2 after Z projection"
        ),
        "Generate mask from C2 after Z projection"
    );

    Dialog.addChoice("Opened fluorescence mask stack:", titles, defaultMask);

    Dialog.addChoice(
        "Threshold mode:",
        newArray(
            "Auto: Default",
            "Auto: Otsu",
            "Auto: Triangle",
            "Auto: Huang",
            "Manual: enter lower/upper",
            "Manual: adjust on preview frame"
        ),
        "Manual: adjust on preview frame"
    );

    Dialog.addNumber("Manual lower threshold:", 0);
    Dialog.addNumber("Manual upper threshold:", 65535);
    Dialog.addNumber("Preview frame for manual threshold:", 1);

    Dialog.addMessage("Step 3b. Generate real signal mask");
    Dialog.addCheckbox("Apply Dilate -> Erode to sign mask", true);
    Dialog.addNumber("Processed sign Dilate / enlarge iterations:", 30);
    Dialog.addNumber("Processed sign Erode / shrink iterations:", 70);
    Dialog.addCheckbox("Add black padding before processed sign Dilate -> Erode", true);
    Dialog.addNumber("Processed sign padding pixels:", 100);
    Dialog.addCheckbox("Preview real signal mask on first frame", true);
    Dialog.addCheckbox("Keep real-signal preview window", false);
    Dialog.addCheckbox("Intersect processed sign with original sign", true);

    Dialog.addMessage("Step 4. Generate background mask from original fluorescence mask");
    Dialog.addNumber("Background mask dilate times:", 50);
    Dialog.addCheckbox("Preview background mask before full processing", false);
    Dialog.addChoice("Background preview mode:", newArray("Frame 1", "Current frame"), "Frame 1");
    Dialog.addCheckbox("Keep generated background mask window after measurement", true);

    Dialog.addMessage("Step 5. Measurement and ratio");
    Dialog.addNumber("Fluorescence ROI enlarge during measurement, pixels:", 0);
    Dialog.addChoice("Ratio direction:", newArray("C1/C2", "C2/C1"), "C1/C2");
    Dialog.addNumber("Baseline frames for Delta Ratio:", 5);
    Dialog.addCheckbox("Output selected parameters to Results", false);

    Dialog.addCheckbox("Clear previous Results + ROI Manager", true);

    Dialog.show();

    originalTitle       = Dialog.getChoice();
    inputImageType     = Dialog.getChoice();
    zProjectionMethod  = Dialog.getChoice();

    fluoMaskSource      = Dialog.getChoice();
    openedFluoMaskTitle = Dialog.getChoice();

    thresholdMode       = Dialog.getChoice();
    manualLower         = Dialog.getNumber();
    manualUpper         = Dialog.getNumber();
    manualPreviewFrame  = round(Dialog.getNumber());

    applySignalMaskProcessing = Dialog.getCheckbox();
    signalDilateN             = round(Dialog.getNumber());
    signalErodeN              = round(Dialog.getNumber());
    useSignalPadding          = Dialog.getCheckbox();
    signalPaddingPx           = round(Dialog.getNumber());
    previewSignalMask         = Dialog.getCheckbox();
    keepSignalPreview         = Dialog.getCheckbox();
    intersectWithRawSign      = Dialog.getCheckbox();

    bgDilateTimes       = round(Dialog.getNumber());
    previewBG           = Dialog.getCheckbox();
    bgPreviewMode       = Dialog.getChoice();
    keepBGMaskWindow    = Dialog.getCheckbox();

    fluoEnlargePx       = Dialog.getNumber();
    ratioDirection      = Dialog.getChoice();
    baselineFrames      = round(Dialog.getNumber());
    outputParamsToResults = Dialog.getCheckbox();

    clearOld            = Dialog.getCheckbox();

    if (bgDilateTimes < 0)
        exit("Background mask dilate times 不能小于 0。");

    if (signalDilateN < 0 || signalErodeN < 0)
        exit("Signal mask Dilate/Erode iterations 不能小于 0。");

    if (signalPaddingPx < 0)
        exit("Signal mask padding pixels 不能小于 0。");

    if (baselineFrames < 1)
        exit("Baseline frames 必须 >= 1。");

    if (manualPreviewFrame < 1)
        manualPreviewFrame = 1;

    if (clearOld) {
        run("Clear Results");
        roiManager("Reset");
    } else {
        roiManager("Reset");
    }

    setOption("BlackBackground", true);

    // ------------------------------------------------------------
    // Early validation: catch wrong opened-mask selection BEFORE Z projection/Dilate.
    // This prevents accidentally using the original .oir/hyperstack as a mask.
    // ------------------------------------------------------------
    if (fluoMaskSource == "Use opened fluorescence mask stack") {
        validateOpenedFluoMaskBasicOrExit(openedFluoMaskTitle, originalTitle);
    }


    baseName = makeSafeName(originalTitle);

    print("\\Clear");
    print("========== Full Workflow Started ==========");
    print("Original image: " + originalTitle);

    // -----------------------------
    // 1. Z-axis Projection or skip if input is already projected
    // -----------------------------
    if (inputImageType == "Already Z-projected image (skip Z projection)") {

        zavgTitle = originalTitle;

        selectWindow(zavgTitle);
        Stack.getDimensions(wInput, hInput, cInput, zInput, tInput);

        if (zInput > 1) {
            exit(
                "你选择了 Already Z-projected image (skip Z projection)，\n" +
                "但当前输入图像仍然有多个 Z slices。\n\n" +
                "当前 Z = " + zInput + "\n\n" +
                "请改选 Raw Z-stack/hyperstack (run Z projection)，\n" +
                "或者先手动完成 Z projection 后再运行宏。"
            );
        }

        print("Z projection skipped.");
        print("Using already Z-projected image: " + zavgTitle);

    } else {

        zavgTitle = createZAverageProjection(originalTitle, baseName, zProjectionMethod);

        print("Z projection method: " + zProjectionMethod);
        print("Z-projected image: " + zavgTitle);
    }

    // -----------------------------
    // 2. Split Channels
    // -----------------------------
    selectWindow(zavgTitle);
    Stack.getDimensions(w0, h0, c0, z0, t0);

    if (c0 < 2) {
        exit("Z projection 后图像的 channel 数小于 2，无法拆分 C1/C2。\n当前 C = " + c0);
    }

    titlesBeforeSplit = getList("image.titles");

    selectWindow(zavgTitle);
    run("Split Channels");

    titlesAfterSplit = getList("image.titles");

    c1Title = findNewSplitChannelTitle(titlesBeforeSplit, titlesAfterSplit, 1);
    c2Title = findNewSplitChannelTitle(titlesBeforeSplit, titlesAfterSplit, 2);

    print("C1 image: " + c1Title);
    print("C2 image: " + c2Title);

    // Expected frame count for all downstream masks.
    expectedFrames = getSequenceLength(c1Title);

    // -----------------------------
    // 3. Get or Generate Fluorescence Mask
    // -----------------------------
    fluoMaskTitle = "";

    if (fluoMaskSource == "Use opened fluorescence mask stack") {

        fluoMaskTitle = openedFluoMaskTitle;
        print("Using opened fluorescence mask: " + fluoMaskTitle);

        // 检查是否误选了原始 .oir / 非二值 mask / 多通道图像
        validateOpenedFluoMaskOrExit(fluoMaskTitle, originalTitle, expectedFrames);

    } else {

        if (fluoMaskSource == "Generate mask from C1 after Z projection") {
            maskSourceTitle = c1Title;
            maskSourceLabel = "C1";
        } else {
            maskSourceTitle = c2Title;
            maskSourceLabel = "C2";
        }

        print("Generating fluorescence mask from: " + maskSourceTitle);
        print("Threshold mode: " + thresholdMode);

        if (thresholdMode == "Manual: adjust on preview frame") {

            nMaskSource = getSequenceLength(maskSourceTitle);

            if (manualPreviewFrame > nMaskSource)
                manualPreviewFrame = nMaskSource;

            gotoSequence(maskSourceTitle, manualPreviewFrame);

            thresholdPreviewTitle = "ThresholdPreview_" + maskSourceLabel + "_" + baseName + "_F" + manualPreviewFrame;

            run("Duplicate...", "title=[" + thresholdPreviewTitle + "] duplicate range=" + manualPreviewFrame + "-" + manualPreviewFrame);

            selectWindow(thresholdPreviewTitle);
            run("Threshold...");

            waitForUser(
                "Manual threshold",
                "请在 Fiji 的 Threshold 窗口中手动调整阈值。\n\n" +
                "调整完成后，不要关闭此预览图像，点击本窗口 OK。\n\n" +
                "宏会读取当前 lower/upper threshold，随后用于整套 stack 生成 fluorescence mask。"
            );

            getThreshold(manualLower, manualUpper);

            if (manualLower == -1 || manualUpper == -1) {
                exit("未检测到有效 threshold。请在 Threshold 窗口中先设置阈值后再点击 OK。");
            }

            print("Manual threshold from preview:");
            print("Lower = " + manualLower);
            print("Upper = " + manualUpper);

            selectWindow(thresholdPreviewTitle);
            close();
        }

        fluoMaskTitle = generateFluorescenceMaskFromChannel(
            maskSourceTitle,
            maskSourceLabel,
            thresholdMode,
            manualLower,
            manualUpper,
            baseName
        );

        print("Generated fluorescence mask: " + fluoMaskTitle);
    }

    // -----------------------------
    // 3b. Generate real signal mask
    // sign = original fluorescence mask
    // processed sign = sign -> Dilate -> Erode
    // real sign = sign AND processed sign
    // Background mask will still be generated from sign, not from real sign.
    // -----------------------------

    rawFluoMaskTitle = fluoMaskTitle;
    signMaskTitle = rawFluoMaskTitle;
    validateMaskBeforeDilateOrExit(signMaskTitle, expectedFrames);

    if (applySignalMaskProcessing) {
        processedSignMaskTitle = generateSignalMaskByDilateErode(
            signMaskTitle,
            signalDilateN,
            signalErodeN,
            useSignalPadding,
            signalPaddingPx,
            false,
            false,
            baseName
        );

        if (intersectWithRawSign) {
            signalMaskTitle = generateRealSignalMaskByIntersection(
                signMaskTitle,
                processedSignMaskTitle,
                previewSignalMask,
                keepSignalPreview,
                baseName
            );
        } else {
            signalMaskTitle = processedSignMaskTitle;
        }
    } else {
        processedSignMaskTitle = signMaskTitle;
        signalMaskTitle = signMaskTitle;
    }

    validateMaskBeforeDilateOrExit(signalMaskTitle, expectedFrames);

    print("Sign mask, original threshold mask: " + signMaskTitle);
    print("Processed sign mask: " + processedSignMaskTitle);
    print("Real signal mask for fluorescence measurement: " + signalMaskTitle);

    // -----------------------------
    // 4. Generate Background Mask
    // IMPORTANT: background is generated from sign/original fluorescence mask,
    // not from processed sign or real sign.
    // -----------------------------

    bgMaskTitle = generateBackgroundMaskByDilateInvert(
        rawFluoMaskTitle,
        bgDilateTimes,
        previewBG,
        bgPreviewMode,
        baseName
    );

    print("Generated background mask: " + bgMaskTitle);

    // -----------------------------
    // 5. Check Stack Length
    // -----------------------------
    nFluoMask = getSequenceLength(signalMaskTitle);
    nBgMask   = getSequenceLength(bgMaskTitle);
    nC1       = getSequenceLength(c1Title);
    nC2       = getSequenceLength(c2Title);

    if (nFluoMask != nBgMask || nFluoMask != nC1 || nFluoMask != nC2) {
        exit("stack 序列长度不一致！\n\n" +
             "Signal mask = " + nFluoMask + "\n" +
             "Background mask   = " + nBgMask + "\n" +
             "C1 image          = " + nC1 + "\n" +
             "C2 image          = " + nC2);
    }

    if (baselineFrames > nC1)
        baselineFrames = nC1;

    print("Frames: " + nC1);
    print("Ratio direction: " + ratioDirection);
    print("Baseline frames: first " + baselineFrames);
    print("Fluorescence ROI enlarge: " + fluoEnlargePx + " pixels");
    print("Real signal mask is used for fluorescence measurement; background mask is generated from sign/original fluorescence mask.");

    // Parameters to be written into every row of Results.
    if (fluoMaskSource == "Use opened fluorescence mask stack") {
        thresholdModeOut = "Opened fluorescence mask";
        thresholdLowerOut = "NA";
        thresholdUpperOut = "NA";
    } else if (indexOf(thresholdMode, "Auto:") == 0) {
        thresholdModeOut = thresholdMode;
        thresholdLowerOut = "Auto_per_frame";
        thresholdUpperOut = "Auto_per_frame";
    } else {
        thresholdModeOut = thresholdMode;
        thresholdLowerOut = manualLower;
        thresholdUpperOut = manualUpper;
    }

    // -----------------------------
    // 6. Measure and Calculate Ratio
    // -----------------------------
    run("Set Measurements...", "mean redirect=None decimal=3");

    ratioValues = newArray(nC1);
    ratioValid  = newArray(nC1);

    startRow = nResults;

    setBatchMode(true);

    for (i = 1; i <= nC1; i++) {

        row = startRow + i - 1;
        arrIndex = i - 1;

        fluoROI = makeTempROI(signalMaskTitle, i, fluoEnlargePx, "Fluo_T" + padNum(i, 4));
        bgROI   = makeTempROI(bgMaskTitle,   i, 0,             "BG_T"   + padNum(i, 4));

        setResult("Frame", row, i);

        if (outputParamsToResults) {
        // Workflow parameters for traceability
        setResult("Input_Image_Type", row, inputImageType);
        setResult("Z_Projection_Method", row, zProjectionMethod);
        setResult("FluoMask_Source", row, fluoMaskSource);
        setResult("Threshold_Mode", row, thresholdModeOut);
        setResult("Threshold_Lower", row, thresholdLowerOut);
        setResult("Threshold_Upper", row, thresholdUpperOut);
        setResult("Threshold_Preview_Frame", row, manualPreviewFrame);
        setResult("Apply_SignalMask_Processing", row, applySignalMaskProcessing);
        setResult("SignalMask_Dilate", row, signalDilateN);
        setResult("SignalMask_Erode", row, signalErodeN);
        setResult("SignalMask_Padding_Used", row, useSignalPadding);
        setResult("SignalMask_Padding_px", row, signalPaddingPx);
        setResult("Intersect_With_Original_Sign", row, intersectWithRawSign);
        setResult("Preview_RealSignalMask", row, previewSignalMask);
        setResult("Keep_SignalPreview", row, keepSignalPreview);
        setResult("BGMask_Dilate", row, bgDilateTimes);
        setResult("Preview_BGMask", row, previewBG);
        setResult("BG_Preview_Mode", row, bgPreviewMode);
        setResult("Keep_BGMask_Window", row, keepBGMaskWindow);
        setResult("FluoROI_Enlarge_px", row, fluoEnlargePx);
        setResult("Ratio_Direction", row, ratioDirection);
        setResult("Baseline_Frames", row, baselineFrames);
        }

        if (fluoROI == -1 || bgROI == -1) {

            if (fluoROI == -1)
                print("Frame " + i + ": fluorescence mask 未检测到 ROI。");

            if (bgROI == -1)
                print("Frame " + i + ": background mask 未检测到 ROI。");

            setResult("C1_Fluo_Mean", row, "NaN");
            setResult("C1_BG_Mean", row, "NaN");
            setResult("C1_BG_Subtracted_Mean", row, "NaN");

            setResult("C2_Fluo_Mean", row, "NaN");
            setResult("C2_BG_Mean", row, "NaN");
            setResult("C2_BG_Subtracted_Mean", row, "NaN");

            if (ratioDirection == "C1/C2")
                setResult("Ratio_C1corr_over_C2corr", row, "NaN");
            else
                setResult("Ratio_C2corr_over_C1corr", row, "NaN");

            ratioValid[arrIndex] = 0;
            continue;
        }

        c1FluoMean = measureMeanWithROI(c1Title, i, fluoROI);
        c1BgMean   = measureMeanWithROI(c1Title, i, bgROI);
        c1CorrMean = c1FluoMean - c1BgMean;

        c2FluoMean = measureMeanWithROI(c2Title, i, fluoROI);
        c2BgMean   = measureMeanWithROI(c2Title, i, bgROI);
        c2CorrMean = c2FluoMean - c2BgMean;

        setResult("C1_Fluo_Mean", row, c1FluoMean);
        setResult("C1_BG_Mean", row, c1BgMean);
        setResult("C1_BG_Subtracted_Mean", row, c1CorrMean);

        setResult("C2_Fluo_Mean", row, c2FluoMean);
        setResult("C2_BG_Mean", row, c2BgMean);
        setResult("C2_BG_Subtracted_Mean", row, c2CorrMean);

        if (ratioDirection == "C1/C2") {

            if (c2CorrMean <= 0) {
                ratioValid[arrIndex] = 0;
                setResult("Ratio_C1corr_over_C2corr", row, "NaN");
                print("Frame " + i + ": C2 corrected mean <= 0，Ratio 输出 NaN。");
            } else {
                ratioValue = c1CorrMean / c2CorrMean;
                ratioValues[arrIndex] = ratioValue;
                ratioValid[arrIndex] = 1;
                setResult("Ratio_C1corr_over_C2corr", row, ratioValue);
            }

        } else {

            if (c1CorrMean <= 0) {
                ratioValid[arrIndex] = 0;
                setResult("Ratio_C2corr_over_C1corr", row, "NaN");
                print("Frame " + i + ": C1 corrected mean <= 0，Ratio 输出 NaN。");
            } else {
                ratioValue = c2CorrMean / c1CorrMean;
                ratioValues[arrIndex] = ratioValue;
                ratioValid[arrIndex] = 1;
                setResult("Ratio_C2corr_over_C1corr", row, ratioValue);
            }
        }
    }

    // -----------------------------
    // 7. Baseline from first N valid ratio values
    // -----------------------------
    baselineSum = 0;
    baselineCount = 0;

    for (j = 0; j < baselineFrames; j++) {
        if (ratioValid[j] == 1) {
            baselineSum = baselineSum + ratioValues[j];
            baselineCount = baselineCount + 1;
        }
    }

    baselineValid = 0;
    baselineMean = 0;

    if (baselineCount == 0) {
        print("警告：前 " + baselineFrames + " 帧中没有有效 Ratio，无法计算 baseline。");
    } else {
        baselineMean = baselineSum / baselineCount;

        if (baselineMean == 0) {
            print("警告：前 " + baselineFrames + " 帧 Ratio 平均值为 0，无法进行归一化。");
        } else {
            baselineValid = 1;
            print("Ratio baseline mean = " + baselineMean);
            print("Valid baseline frames = " + baselineCount + " / " + baselineFrames);
        }
    }

    // -----------------------------
    // 8. Output normalized Delta Ratio
    // -----------------------------
    for (i = 1; i <= nC1; i++) {

        row = startRow + i - 1;
        arrIndex = i - 1;

        if (baselineValid == 1) {

            setResult("Ratio_First5Mean", row, baselineMean);

            if (ratioValid[arrIndex] == 1) {
                deltaRatio = (ratioValues[arrIndex] - baselineMean) / baselineMean;
                setResult("Ratio_Delta_over_First5Mean", row, deltaRatio);
            } else {
                setResult("Ratio_Delta_over_First5Mean", row, "NaN");
            }

        } else {

            setResult("Ratio_First5Mean", row, "NaN");
            setResult("Ratio_Delta_over_First5Mean", row, "NaN");
        }
    }

    updateResults();

    setBatchMode(false);

    roiManager("Reset");

    if (!keepBGMaskWindow) {
        selectWindow(bgMaskTitle);
        close();
        print("Background mask window closed.");
    }

    print("========== Full Workflow Finished ==========");
    print("Results table updated.");
}


// ============================================================
// Step 1. Z Projection
// ============================================================

function createZAverageProjection(originalTitle, baseName, zProjectionMethod) {

    selectWindow(originalTitle);
    Stack.getDimensions(w, h, c, z, t);

    methodSafe = makeSafeName(zProjectionMethod);
    desiredTitle = "ZPROJ_" + methodSafe + "_" + baseName;

    if (z > 1) {

        run("Z Project...", "projection=[" + zProjectionMethod + "] all");

        actualTitle = getTitle();
        print("Z Project actual output title: " + actualTitle);

        rename(desiredTitle);

        finalTitle = getTitle();
        print("Z-projected image renamed to: " + finalTitle);

        return finalTitle;

    } else {

        run("Duplicate...", "title=[" + desiredTitle + "] duplicate");

        finalTitle = getTitle();
        print("No Z stack detected. Duplicated image as: " + finalTitle);

        return finalTitle;
    }
}


// ============================================================
// Step 2. Find Split Channel Windows
// ============================================================

function findNewSplitChannelTitle(titlesBefore, titlesAfter, channelIndex) {

    prefix = "C" + channelIndex + "-";

    for (ii = 0; ii < lengthOf(titlesAfter); ii++) {

        titleNow = titlesAfter[ii];

        if (!arrayContains(titlesBefore, titleNow)) {

            if (indexOf(titleNow, prefix) == 0) {
                return titleNow;
            }
        }
    }

    for (ii = 0; ii < lengthOf(titlesAfter); ii++) {

        titleNow = titlesAfter[ii];

        if (indexOf(titleNow, prefix) == 0) {
            return titleNow;
        }
    }

    exit("未找到 Split Channels 后生成的 C" + channelIndex + " 窗口。\n请检查 Z projection 图像是否确实包含至少 2 个 channel。");
}


function arrayContains(arr, value) {

    for (ii = 0; ii < lengthOf(arr); ii++) {
        if (arr[ii] == value)
            return true;
    }

    return false;
}


// ============================================================
// Step 3. Generate Fluorescence Mask from C1/C2
// ============================================================

function generateFluorescenceMaskFromChannel(
    channelTitle,
    sourceLabel,
    thresholdMode,
    manualLower,
    manualUpper,
    baseName
) {

    maskTitle = "FluoMask_from_" + sourceLabel + "_" + baseName;

    selectWindow(channelTitle);
    run("Duplicate...", "title=[" + maskTitle + "] duplicate");

    maskTitle = getTitle();

    selectWindow(maskTitle);
    setOption("BlackBackground", true);

    if (thresholdMode == "Manual: enter lower/upper" || thresholdMode == "Manual: adjust on preview frame") {

        setThreshold(manualLower, manualUpper);
        run("Convert to Mask", "black");

    } else {

        method = getAutoThresholdMethod(thresholdMode);
        run("Convert to Mask", "method=" + method + " background=Dark calculate black");
    }


    return maskTitle;
}


function getAutoThresholdMethod(thresholdMode) {

    if (thresholdMode == "Auto: Default")
        return "Default";

    if (thresholdMode == "Auto: Otsu")
        return "Otsu";

    if (thresholdMode == "Auto: Triangle")
        return "Triangle";

    if (thresholdMode == "Auto: Huang")
        return "Huang";

    return "Default";
}



// ============================================================
// ============================================================
// Fast preview helper
// Copy exactly one frame/slice from an 8-bit mask stack into a new 2D image.
// This is safer than Duplicate... range=... for T-series/hyperstack previews.
// ============================================================

function duplicateFrameAs2DMask(srcTitle, frameIndex, outTitle) {

    selectWindow(srcTitle);
    Stack.getDimensions(w, h, c, z, t);

    if (c != 1) {
        exit("Preview source mask should be single-channel. Current C = " + c);
    }

    nSeq = getSequenceLength(srcTitle);

    if (frameIndex < 1)
        frameIndex = 1;

    if (frameIndex > nSeq)
        frameIndex = nSeq;

    gotoSequence(srcTitle, frameIndex);

    run("Select All");
    run("Copy");
    run("Select None");

    newImage(outTitle, "8-bit black", w, h, 1);
    selectWindow(outTitle);
    run("Paste");
    run("Select None");

    setOption("BlackBackground", true);
    resetMinAndMax();
}


// Step 3b-a. Generate processed sign mask
// sign -> optional black padding -> Dilate N times -> Erode M times -> crop back
// Padding prevents boundary loss when a mask touches the image edge.
// Default tested setting: Dilate 30, Erode 70
// ============================================================

function generateSignalMaskByDilateErode(
    srcMaskTitle,
    dilN,
    eroN,
    usePadding,
    paddingPx,
    doPreview,
    keepPreview,
    baseName
) {

    selectWindow(srcMaskTitle);
    setOption("BlackBackground", true);
    getDimensions(srcW, srcH, srcC, srcZ, srcT);

    previewTitle = "Preview_ProcessedSign_" + baseName + "_Dil" + dilN + "_Ero" + eroN;
    finalTitle = "ProcessedSign_" + baseName + "_Dil" + dilN + "_Ero" + eroN;

    if (usePadding && paddingPx > 0) {
        previewTitle = previewTitle + "_Pad" + paddingPx;
        finalTitle = finalTitle + "_Pad" + paddingPx;
    }

    previewTitle = previewTitle + "_F1";

    if (doPreview) {

        // Use a true single-frame 2D copy for preview.
        // This avoids accidentally processing the whole time series.
        duplicateFrameAs2DMask(srcMaskTitle, 1, previewTitle);

        if (usePadding && paddingPx > 0)
            addBlackPaddingCanvas(previewTitle, paddingPx);

        processSingleSliceDilateErode(previewTitle, dilN, eroN);

        if (usePadding && paddingPx > 0)
            cropCanvasBackToOriginal(previewTitle, srcW, srcH);

        showMessageWithCancel(
            "Signal mask 预览完成",
            "已生成第一帧 signal mask 预览：\n" + previewTitle + "\n\n" +
            "操作顺序：\n" +
            "1. Add black padding x " + paddingPx + " pixels: " + usePadding + "\n" +
            "2. Dilate / enlarge x " + dilN + "\n" +
            "3. Erode / shrink x " + eroN + "\n" +
            "4. Crop back to original image size\n\n" +
            "该 mask 将用于测量 fluorescence signal。\n" +
            "background mask 会从原始 fluorescence mask 另行生成。\n\n" +
            "点击 OK 继续；点击 Cancel 终止。"
        );

        if (!keepPreview) {
            selectWindow(previewTitle);
            close();
        }
    }

    selectWindow(srcMaskTitle);
    run("Duplicate...", "title=[" + finalTitle + "] duplicate");
    finalTitle = getTitle();

    if (usePadding && paddingPx > 0)
        addBlackPaddingCanvas(finalTitle, paddingPx);

    processWholeStackDilateErodeWithProgress(finalTitle, dilN, eroN);

    if (usePadding && paddingPx > 0)
        cropCanvasBackToOriginal(finalTitle, srcW, srcH);

    selectWindow(finalTitle);
    resetMinAndMax();

    return finalTitle;
}


function addBlackPaddingCanvas(title, paddingPx) {

    if (paddingPx <= 0)
        return;

    selectWindow(title);
    getDimensions(w, h, c, z, t);

    newW = w + 2 * paddingPx;
    newH = h + 2 * paddingPx;

    setOption("BlackBackground", true);
    run("Canvas Size...", "width=" + newW + " height=" + newH + " position=Center zero");
}


function cropCanvasBackToOriginal(title, originalW, originalH) {

    selectWindow(title);
    setOption("BlackBackground", true);
    run("Canvas Size...", "width=" + originalW + " height=" + originalH + " position=Center zero");
}


function processSingleSliceDilateErode(title, dilN, eroN) {

    selectWindow(title);
    setOption("BlackBackground", true);

    totalSteps = dilN + eroN;
    if (totalSteps < 1)
        totalSteps = 1;

    for (k = 1; k <= dilN; k++) {
        showStatus("Signal mask preview: Dilate " + k + "/" + dilN);
        showProgress(k - 1, totalSteps);
        run("Dilate");
    }

    for (k = 1; k <= eroN; k++) {
        showStatus("Signal mask preview: Erode " + k + "/" + eroN);
        showProgress(dilN + k - 1, totalSteps);
        run("Erode");
    }

    showProgress(totalSteps, totalSteps);
    showStatus("Signal mask preview done");
}


function processWholeStackDilateErodeWithProgress(title, dilN, eroN) {

    selectWindow(title);
    setOption("BlackBackground", true);

    totalSteps = dilN + eroN;
    if (totalSteps < 1)
        totalSteps = 1;

    for (k = 1; k <= dilN; k++) {
        showStatus("Signal mask full stack: Dilate " + k + "/" + dilN);
        showProgress(k - 1, totalSteps);
        run("Dilate", "stack");
    }

    for (k = 1; k <= eroN; k++) {
        showStatus("Signal mask full stack: Erode " + k + "/" + eroN);
        showProgress(dilN + k - 1, totalSteps);
        run("Erode", "stack");
    }

    showProgress(totalSteps, totalSteps);
    showStatus("Signal mask full stack done");
}



// ============================================================
// Step 3b-b. Generate real signal mask by intersection
// real sign = sign AND processed sign
// ============================================================

function generateRealSignalMaskByIntersection(
    signMaskTitle,
    processedSignMaskTitle,
    doPreview,
    keepPreview,
    baseName
) {

    realTitle = "RealSign_" + baseName;

    // Full-stack intersection: real sign = sign AND processed sign
    selectWindow(signMaskTitle);
    imageCalculator("AND create stack", signMaskTitle, processedSignMaskTitle);
    rename(realTitle);
    realTitle = getTitle();

    selectWindow(realTitle);
    setOption("BlackBackground", true);
    resetMinAndMax();

    if (doPreview) {

        signPreviewTitle = "Preview_Sign_for_AND_" + baseName + "_F1";
        processedPreviewTitle = "Preview_ProcessedSign_for_AND_" + baseName + "_F1";
        realPreviewTitle = "Preview_RealSign_AND_" + baseName + "_F1";

        duplicateFrameAs2DMask(signMaskTitle, 1, signPreviewTitle);
        duplicateFrameAs2DMask(processedSignMaskTitle, 1, processedPreviewTitle);

        imageCalculator("AND create", signPreviewTitle, processedPreviewTitle);
        rename(realPreviewTitle);
        realPreviewTitle = getTitle();
        resetMinAndMax();

        // Close temporary previews used only for AND calculation.
        selectWindow(signPreviewTitle);
        close();
        selectWindow(processedPreviewTitle);
        close();

        showMessageWithCancel(
            "Real signal mask 预览完成",
            "已生成第一帧 real signal mask 预览：\n" + realPreviewTitle + "\n\n" +
            "计算逻辑：\n" +
            "real sign = sign AND processed sign\n\n" +
            "其中：\n" +
            "sign = threshold 后的原始 fluorescence mask\n" +
            "processed sign = sign Dilate -> Erode\n\n" +
            "该 real sign mask 将用于测量 fluorescence signal。\n" +
            "background mask 将从 sign 另行 Dilate -> Invert 生成。\n\n" +
            "点击 OK 继续；点击 Cancel 终止。"
        );

        if (!keepPreview) {
            selectWindow(realPreviewTitle);
            close();
        }
    }

    return realTitle;
}


// ============================================================
// Step 4. Generate Background Mask
// fluorescence mask -> Dilate N times -> Invert
// ============================================================

function generateBackgroundMaskByDilateInvert(
    fluoMaskTitle,
    dilN,
    doPreview,
    previewMode,
    baseName
) {

    selectWindow(fluoMaskTitle);

    currentSeq = getCurrentSequenceIndex(fluoMaskTitle);

    previewSlice = 1;
    if (previewMode == "Current frame")
        previewSlice = currentSeq;

    nSeq = getSequenceLength(fluoMaskTitle);

    if (previewSlice < 1)
        previewSlice = 1;

    if (previewSlice > nSeq)
        previewSlice = nSeq;

    previewTitle = "Preview_BGMask_" + baseName + "_Dil" + dilN + "_F" + previewSlice;
    bgTitle = "BGMask_" + baseName + "_Dil" + dilN + "_Inv";

    if (doPreview) {

        showStatus("Preparing background mask preview...");
        showProgress(0, 100);

        // Use a true single-frame 2D copy for preview.
        // This avoids accidentally processing the whole time series.
        duplicateFrameAs2DMask(fluoMaskTitle, previewSlice, previewTitle);

        processSingleSlicePreview(previewTitle, dilN, true);

        showProgress(100, 100);
        showStatus("Background mask preview ready.");

        showMessageWithCancel(
            "Background mask 预览完成",
            "已生成预览窗口：\n" + previewTitle + "\n\n" +
            "请检查 Dilate + Invert 后的 background mask 是否合适。\n\n" +
            "点击 OK 继续生成整套 background mask 并进行测量；\n" +
            "点击 Cancel 终止。"
        );

        selectWindow(previewTitle);
        close();
    }

    selectWindow(fluoMaskTitle);

    showStatus("Generating full background mask...");
    run("Duplicate...", "title=[" + bgTitle + "] duplicate");

    bgTitle = getTitle();

    processWholeStackWithProgress(bgTitle, dilN, true);

    selectWindow(bgTitle);
    showStatus("Background mask generated.");

    return bgTitle;
}


// ============================================================
// Preview and full-stack morphology processing
// ============================================================

function processSingleSlicePreview(title, dilN, doInvert) {

    selectWindow(title);

    extraStep = 0;
    if (doInvert)
        extraStep = 1;

    totalSteps = dilN + extraStep;
    if (totalSteps < 1)
        totalSteps = 1;

    for (k = 1; k <= dilN; k++) {
        showStatus("Preview dilate " + k + "/" + dilN);
        showProgress(k - 1, totalSteps);
        run("Dilate");
    }

    if (doInvert) {
        showStatus("Preview invert");
        showProgress(dilN, totalSteps);
        run("Invert");
    }

    showProgress(totalSteps, totalSteps);
    showStatus("Preview done");
}


function processWholeStackWithProgress(title, dilN, doInvert) {

    selectWindow(title);

    extraStep = 0;
    if (doInvert)
        extraStep = 1;

    totalSteps = dilN + extraStep;
    if (totalSteps < 1)
        totalSteps = 1;

    for (k = 1; k <= dilN; k++) {
        showStatus("Dilating full background mask... round " + k + "/" + dilN);
        showProgress(k - 1, totalSteps);

        run("Dilate", "stack");

        showProgress(k, totalSteps);
    }

    if (doInvert) {
        showStatus("Inverting full background mask...");
        showProgress(dilN, totalSteps);

        run("Invert", "stack");

        showProgress(totalSteps, totalSteps);
    }

    showStatus("Full stack processing done.");
}


// ============================================================
// Measurement helper functions
// ============================================================

function makeTempROI(maskTitle, idx, enlargePx, roiName) {

    gotoSequence(maskTitle, idx);

    run("Select None");
    run("Create Selection");

    if (selectionType() == -1) {
        return -1;
    }

    if (enlargePx != 0) {
        run("Enlarge...", "enlarge=" + enlargePx);
    }

    roiManager("Add");
    last = roiManager("count") - 1;

    roiManager("Select", last);
    roiManager("Rename", roiName);

    return last;
}


function measureMeanWithROI(imageTitle, idx, roiIndex) {

    gotoSequence(imageTitle, idx);

    roiManager("Select", roiIndex);

    getStatistics(area, mean, min, max, std);

    return mean;
}


// ============================================================
// Stack navigation helper functions
// ============================================================

function getSequenceLength(title) {

    selectWindow(title);

    Stack.getDimensions(w, h, c, z, t);

    if (t > 1)
        return t;
    else if (z > 1)
        return z;
    else
        return 1;
}


function gotoSequence(title, idx) {

    selectWindow(title);

    Stack.getDimensions(w, h, c, z, t);

    if (t > 1) {
        Stack.setPosition(1, 1, idx);
    } else if (z > 1) {
        Stack.setPosition(1, idx, 1);
    } else {
        setSlice(idx);
    }
}


function getCurrentSequenceIndex(title) {

    selectWindow(title);

    Stack.getDimensions(w, h, c, z, t);
    Stack.getPosition(curC, curZ, curT);

    if (t > 1)
        return curT;
    else if (z > 1)
        return curZ;
    else
        return getSliceNumber();
}


// ============================================================
// Mask validation helper functions
// ============================================================

function validateOpenedFluoMaskBasicOrExit(maskTitle, originalTitle) {

    // 1. Most common mistake: choosing the original image as the opened mask.
    if (maskTitle == originalTitle) {

        msg =
            "Fluorescence mask 选择错误。\n\n" +
            "当前你选择的是原始图像：\n" +
            maskTitle + "\n\n" +
            "但当前模式是：Use opened fluorescence mask stack。\n\n" +
            "这里必须选择已经生成好的二值 fluorescence mask stack，\n" +
            "而不是原始 .oir / 原始 hyperstack。\n\n" +
            "请重新运行宏，并在 Opened fluorescence mask stack 中选择正确的 mask。";

        showMessage("Fluorescence mask 选择错误", msg);
        exit("Fluorescence mask 选择错误：你选择的是原始图像，而不是二值 mask。请重新运行宏并选择正确的 mask。");
    }

    // 2. Basic image-type check before doing any time-consuming processing.
    selectWindow(maskTitle);
    Stack.getDimensions(w, h, c, z, t);
    bd = bitDepth();

    errorMsg = "";

    if (bd != 8) {
        errorMsg = errorMsg +
            "图像类型错误：当前 bit depth = " + bd + "-bit。\n" +
            "Fluorescence mask 应该是 8-bit 二值图像。\n\n";
    }

    if (c != 1) {
        errorMsg = errorMsg +
            "通道数错误：当前 C = " + c + "。\n" +
            "Fluorescence mask 应该是单通道图像，即 C = 1。\n\n";
    }

    if (errorMsg != "") {

        msg =
            "当前选择的 fluorescence mask 不适合用于后续分析。\n\n" +
            "选中的图像为：\n" +
            maskTitle + "\n\n" +
            errorMsg +
            "请确认你选择的是已经生成好的二值 mask stack，而不是原始 .oir / 原始 hyperstack。";

        showMessage("Fluorescence mask 选择错误", msg);
        exit("Fluorescence mask 选择错误：请选择 8-bit、单通道的二值 mask stack。");
    }
}


function validateOpenedFluoMaskOrExit(maskTitle, originalTitle, expectedFrames) {

    if (maskTitle == originalTitle) {

        msg =
            "Fluorescence mask 选择错误。\n\n" +
            "你当前选择的是原始图像：\n" +
            maskTitle + "\n\n" +
            "但当前模式是：Use opened fluorescence mask stack。\n\n" +
            "这里应该选择已经生成好的二值 fluorescence mask stack，\n" +
            "而不是原始 .oir / 原始 hyperstack。\n\n" +
            "请重新运行宏，并在 Opened fluorescence mask stack 中选择正确的 mask。";

        showMessage("Fluorescence mask 选择错误", msg);
        exit(msg);
    }

    validateMaskBeforeDilateOrExit(maskTitle, expectedFrames);
}


function validateMaskBeforeDilateOrExit(maskTitle, expectedFrames) {

    selectWindow(maskTitle);

    Stack.getDimensions(w, h, c, z, t);

    bd = bitDepth();
    nSeq = getSequenceLength(maskTitle);

    errorMsg = "";

    if (bd != 8) {
        errorMsg = errorMsg +
            "图像类型错误：当前 bit depth = " + bd + "-bit。\n" +
            "Dilate 要求 mask 为 8-bit 图像。\n\n";
    }

    if (c != 1) {
        errorMsg = errorMsg +
            "通道数错误：当前 C = " + c + "。\n" +
            "Fluorescence mask 应该是单通道图像，即 C = 1。\n\n";
    }

    if (nSeq != expectedFrames) {
        errorMsg = errorMsg +
            "序列长度不匹配：\n" +
            "Fluorescence mask frames = " + nSeq + "\n" +
            "C1/C2 image frames = " + expectedFrames + "\n\n";
    }

    if (errorMsg != "") {

        msg =
            "当前选择的 fluorescence mask 不适合用于后续 Dilate + Invert。\n\n" +
            "选中的图像为：\n" +
            maskTitle + "\n\n" +
            errorMsg +
            "请确认你选择的是已经生成好的二值 mask stack，通常应满足：\n" +
            "1. 8-bit\n" +
            "2. 单通道 C=1\n" +
            "3. frame 数与 C1/C2 一致\n" +
            "4. 不是原始 .oir / 原始 hyperstack";

        showMessage("Fluorescence mask 选择错误", msg);
        exit(msg);
    }
}


// ============================================================
// String helper functions
// ============================================================



function makeSafeName(name) {

    s = name;

    s = replace(s, " ", "_");
    s = replace(s, ":", "_");
    s = replace(s, "/", "_");
    s = replace(s, "\\", "_");
    s = replace(s, "[", "_");
    s = replace(s, "]", "_");
    s = replace(s, "(", "_");
    s = replace(s, ")", "_");

    return s;
}


function padNum(n, digits) {

    s = "" + n;

    while (lengthOf(s) < digits)
        s = "0" + s;

    return s;
}


function minOf(a, b) {

    if (a < b)
        return a;
    else
        return b;
}
