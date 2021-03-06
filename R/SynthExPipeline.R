SynthExPipeline <- function(tumor, normal, bin.size, bedTools.dir, genotype.file,
                            result.dir = NULL, working.dir = NULL, verbose = FALSE,
                            saveplot = TRUE, plotNormalized = TRUE,
                            rm.centromere = TRUE, targetAnnotateBins = NULL, centromereBins = NULL, chrX = FALSE,
                            report = TRUE, plot = TRUE, prefix = NULL, reads.threshold = 25, vcf = TRUE,
                            adjust.cutoff = 1.2, seg.count = 200, segmentMethod = "CBS",
                            smoothk = 10, ratio.cutoff = 0.05, K = 1,
                            WGD = 1.35, pos.prop.threhold = 0.6, pos.log2ratio.threhold = 0.75,
                            prop.threshold = 0.0005, delta = 0.1, maf.control = 0.01,
                            tau = 2, sigma = 0.1, len.threshold.K = 10,  group.length.threshold = 2,
                            gain.threshold = log2(1.2), loss.threshold = log2(0.8), lwd = 5){

  ratioCorrectedBias <- SynthExcorrectBias(tumor, normal, bin.size = bin.size, rm.centromere = rm.centromere,
             targetAnnotateBins = targetAnnotateBins, saveplot = saveplot, centromereBins = centromereBins,
             chrX = chrX, plot = plot, result.dir = result.dir, working.dir = working.dir, K =K,
             prefix = prefix, reads.threshold = reads.threshold,
             verbose=verbose)

  if(verbose == TRUE) {
    message("Bias correction finished.")
    message ("ratioCorrectedBias: ")
    str(ratioCorrectedBias)
#    message ("Unique ratioCorrectedBias$Ratio$chr: ", paste(unique(ratioCorrectedBias$Ratio$chr),collapse=', '))

  }

  if(!is.null(genotype.file)){
    ratioNormalized <- normalization(ratioCorrectedBias, bedTools.dir = bedTools.dir, genotype.file = genotype.file, vcf = vcf,
          working.dir = working.dir, result.dir = result.dir, cutoff = reads.threshold, plot = plot, saveplot = saveplot,
          prefix = prefix,  adjust.cutoff = adjust.cutoff, seg.count = seg.count)
    if(verbose == TRUE) message("Normalization finished.")
    ratioToSeg <- ratioNormalized
  } else {
    ratioToSeg <- ratioCorrectedBias
  }

  Seg <- createSegments(ratioToSeg, segmentMethod,verbose=verbose)


  if(verbose == TRUE) {
    message("Segmentation finished.")
#    message("str(Seg)=")
#    str(Seg)
#    message ("Unique Seg$segmentNormalized$chr: ", paste(unique(Seg$segmentNormalized$chr),collapse=', '))
  }

  Segments <- singleCNreport(Seg, report = report, result.dir = result.dir, saveplot = saveplot,
           prefix = prefix, plotNormalized = plotNormalized, WGD = WGD, pos.prop.threhold = pos.prop.threhold,
           pos.log2ratio.threhold = pos.log2ratio.threhold,verbose=verbose)

  if(verbose == TRUE) message("singleCNreport finished.")

  if(!is.null(genotype.file)){
    PurityCorrected <- purityEstimate(Segments, working.dir = working.dir, result.dir = result.dir, bedTools.dir = bedTools.dir,
     prefix = prefix, report = report, prop.threshold = prop.threshold, delta = delta, maf.control = maf.control,
     tau = tau, sigma = sigma, len.threshold.K = len.threshold.K, group.length.threshold = group.length.threshold,
     gain.threshold = gain.threshold, loss.threshold = loss.threshold, Normalized = plotNormalized)
    if(verbose == TRUE) message("Purity estimation finished.")
    genomeplot <- chromosomeView(PurityCorrected, prefix = prefix, result.dir = result.dir, saveplot = saveplot, lwd = lwd)
    Segments <- PurityCorrected
  }

  if(verbose == TRUE) message("Report can be found at: ", result.dir)

  return(Segments)

}

