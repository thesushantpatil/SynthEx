WGS_normalization <- function(tumor.file, normal.file, bin.size = 100000, rm.centromere = TRUE,
                              centromereBins = NULL, plot = TRUE, reads.threshold = 50, cluster1.prop = 0.025, bedTools.dir,
                              genotype.file,  vcf = TRUE, cutoff = 10, result.dir = NULL, prefix = NULL, adjust.cutoff = 1.2){

  options(scipen = 50)
  if(is.null(result.dir)) result.dir <- getwd()
  #ratio of tumor/normal coverage from bins
  tumor.data <- read.delim(tumor.file, header = F, stringsAsFactors = F)
  colnames(tumor.data) <- c("chr", "start", "end", "reads")

  tumor.data[, 1] <- gsub("^chr", "", tumor.data[, 1])

  if(tumor.data[1, "end"] - tumor.data[1, "start"] != bin.size){
    stop("\"bin.size\" should match with the input file!")
  }

  y <- read.delim(normal.file, header = F, stringsAsFactors = F)
  colnames(y) <- c("chr", "start", "end", "reads")
  factor <- sum(tumor.data[, "reads"])/sum(y[, "reads"])

  if(factor <= 0.75 | factor >= 1.5){
    y[, "normalized"] <- round(y[, "reads"]*factor, 3)
    y[y[, "normalized"] < reads.threshold, "normalized"] <- 0
    ratio <- tumor.data[, "reads"]/y[, "normalized"]
  } else {
    ratio <- tumor.data[, "reads"]/y[, "reads"]
  }
  ratio[is.infinite(ratio) | is.nan(ratio)] <- NA
  ratio.IDs <- paste0(tumor.data[, "chr"], ":", tumor.data[, "start"])
  ratio.res <- data.frame(tumor.data[, c("chr", "start", "end")], ratio)

  if(rm.centromere == TRUE) {
    if(is.null(centromereBins)){
      load(centromere.annotations)
    } else {
      centromere <- read.delim(centromereBins, header = F, stringsAsFactors = F)
    }
    centromere.IDs <- paste0(centromere[, 1], ":", centromere[, 2])
    ratio.IDs <- paste0(ratio.res[, "chr"], ":", ratio.res[, "start"])
    ratio.res <- ratio.res[! ratio.IDs%in%centromere.IDs, ]
  }

  ratio.bed <- ratio.res

  ratio.bed[,2] <- ratio.bed[, 2] -1

  write.table(ratio.bed, file.path (result.dir, "adjusted.ratio.bed"), col.names = F, row.names = F, sep = "\t", quote = F)


  ######### calculate MAF from VCF file #########
  ff <- paste0("cat ", genotype.file, " | python ", freebayes_to_bed, " ", cutoff, " 0.05  > ",
               file.path (working.dir, "tumor.MAF.highcut.bed"))
  system(ff)

  #Creates the intersect(using intersectBed) of MAF + adjusted bin ratios
  ff <- paste0(bedTools.dir, " -a ", file.path (working.dir, "tumor.MAF.highcut.bed"),
               " -b ", file.path (working.dir, "adjusted.ratio.bed"),
               " -wa -wb > ",  file.path (working.dir, "tumor.MAF.ratio.bed"))
  system(ff)


  ##########
  ##########
  tumor.maf.ratio <- read.delim(file.path (working.dir, "tumor.MAF.ratio.bed"), header = F)

  tumor.maf.ratio[, 1] <- gsub("^chr", "", tumor.maf.ratio[, 1])

  tumor.maf.ratio <- tumor.maf.ratio[tumor.maf.ratio[, 1] %in% c(1:(TargetAnnotations$numchrom - 1)), ]
  segments <- paste0(tumor.maf.ratio[, 5], ":", tumor.maf.ratio[, 6])
  median.MAF <- tapply(tumor.maf.ratio[, 4], segments, median)
  median.MAF.segments <- data.frame(names(median.MAF), median.MAF)
  colnames(median.MAF.segments) <- c("segments", "MAF")
  ratio.segments <- data.frame(segments, tumor.maf.ratio[, 8])
  ratio.segments <- ratio.segments[!duplicated(ratio.segments), ]
  colnames(ratio.segments) <- c("segments", "ratio")
  merged.segments <- merge(median.MAF.segments, ratio.segments, by.x = "segments", by.y = "segments")
  merged.segments <- merged.segments[!is.na(merged.segments[, 2]) & !is.na(merged.segments[, 3]) & is.finite(merged.segments[, 3]), ]

  all.median.ratio <- merged.segments[merged.segments$MAF > 0.45, "ratio"]
  all.median.AF <- merged.segments[merged.segments$MAF > 0.45, "MAF"]

  adjust <- median(all.median.ratio, na.rm = T)

  median.ratio <- all.median.ratio[all.median.ratio < 2.5*adjust]
  median.AF <- all.median.AF[all.median.ratio < 2.5*adjust]

  rr <- density(median.ratio, na.rm = T)
  adjust2 <- rr$x[which.max(rr$y)]
  sorted.median.ratio <- sort(median.ratio)

  if( ! all(sorted.median.ratio == 1) ){

    suppressPackageStartupMessages(require(mclust))
    #Identify 2n cluster - Diploid reference#
    mccluster <- Mclust(sorted.median.ratio, G = 1:5, prior = priorControl(functionName = "defaultPrior", shrinkage = 0.1))
    means <- mccluster$parameters$mean
    prop <- mccluster$parameters$pro

    prop <- prop[order(means)]
    means <- sort(means)

    #Adjustment

    adjust3 <- NA
    if (length(means) == 2){
      adjust3 <- ifelse(prop[1] > 0.1 & abs(means[1] - adjust2) >= 0.2, means[1], NA)
    } else if (length(means) > 2){
      adjust3 <- ifelse((prop[1] > 0.1 & abs(means[1] - adjust2) >= 0.2) | (prop[1] > 0.5), means[1], NA)
    }
    if(length(means) > 2 & prop[1] < 0.1 & means[2] < 1){
      adjust3 <- ifelse(abs(means[2] - means[3]) >= 0.2, means[2], NA)
    }
    if(length(median.ratio[median.ratio == 0]) > 50){
      adjust2 <- 1
    } else if(!is.na(adjust3)) {
      adjust2 <- adjust3
    }

    if(adjust2 > adjust.cutoff | adjust2 > adjust) adjust2 <- adjust

    if(length(median.ratio) < seg.count) adjust2 <- 1

    adjust2 <- as.numeric(round(adjust2, 3))
  } else {
    adjust2 <- 1
  }

  AF.ratio <- data.frame(median.AF, median.ratio, row.names = NULL)

  suppressPackageStartupMessages(require(ggplot2))
  suppressPackageStartupMessages(require(gridExtra))
  theme_set(theme_bw())

  if(plot == TRUE) {
    #scatterplot of x and y variables
    if(saveplot == TRUE){
      if(!is.null(prefix)){
        pdf(file.path (result.dir, paste0(prefix, "-BaselinePlot.pdf")), width = 12, height = 6)
      } else {
        pdf(file.path (result.dir, "BaselinePlot.pdf"), width = 12, height = 6)
      }
    }
    scatter <- ggplot(AF.ratio, aes(median.AF, median.ratio)) +  geom_point() +  theme(legend.position = c(1, 1), legend.justification = c(1, 1)) + xlab("median MAF") + ylab("Tumor/Normal Ratio")
    ypos <- max(density(median.ratio)$y)*0.6
    adjust.data <- data.frame(adjust2, ypos)
    #marginal density of y - plot on the right
    plot_right <- ggplot(AF.ratio, aes(median.ratio, fill = "red")) + geom_density(alpha = .5) + coord_flip() + theme(legend.position = "none")  + geom_vline(xintercept = adjust2, color = "blue", size = 2) + ylab("Density") + xlab("Tumor/Normal Ratio") + geom_text(aes(adjust2 + 0.3, ypos, label = "Baseline: \n Copy Number = 2"), data = adjust.data)
    grid.arrange(scatter, plot_right, ncol = 2, nrow = 1, widths = c(2, 2))
    if(saveplot == TRUE){
      dev.off()
    }
  }

  Ratio <- ratio.res
  colnames(CorrectedRatio) <- c("chr", "start", "end", "ratio")
  Ratio[, "normalized"] <- round(Ratio[, "ratio"]/adjust2, 3)
  ratioNormalized <- list(Ratio, adjust2, FALSE, "WGS")
  names(ratioNormalized) <- c("Ratio", "Adjust", "Synthetic", "Type")

  class(ratioNormalized) <- "RatioNormalized"
  return(ratioNormalized)

}
