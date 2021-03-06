#' Wrapper class for gene expression object for JSON.
#'
#' @param data numeric matrix
#' @param sample_labels Labels of samples in expression data
#' @param gene_labels Lables of genes in expression data
#' @return ServerExpression object
ServerExpression <- function(data, sample_labels, gene_labels) {
            .Object <- new("ServerExpression", data=data,
                           sample_labels=sample_labels,
                           gene_labels=gene_labels)
            return(.Object)
            }

#' Wrapper class for Signature Projection Matrix
#'
#' @param zscores numeric matrix
#' @param pvals numeric matrix
#' @param proj_labels Projection names
#' @param sig_labels Names of signatures
#' @return ServerSigProjMatrix object
ServerSigProjMatrix <- function(zscores, pvals, proj_labels, sig_labels) {
            .Object <- new("ServerSigProjMatrix",
                           zscores = zscores, pvals = pvals,
                           proj_labels = proj_labels, sig_labels = sig_labels)
            return(.Object)
            }

#' Converts Signature object to JSON
#' @importFrom jsonlite toJSON
#' @param sig Signature object
#' @return JSON formatted Signature object.
signatureToJSON <- function(sig) {

    # Pass in a Signature object from a FastProject Object to be converted into a JSON object
    sig@sigDict <- as.list(sig@sigDict)

    json <- toJSON(sig, force=TRUE, pretty=TRUE, auto_unbox=TRUE)
    return(json)

}

#' Convertes expression matrix to JSON
#' @importFrom jsonlite toJSON
#' @param expr Expression Matrix
#' @param geneList optional list of genes to subset from expr
#' @return (Potentially) subsetted expression matrix
expressionToJSON <- function(expr, geneList=NULL, zscore=FALSE) {

    if (!is.null(geneList)) {
        geneList = intersect(geneList, rownames(expr))
        expr <- expr[geneList,, drop=FALSE]
    }

    if (zscore) {
        rm <- matrixStats::rowMeans2(expr)
        rsd <- matrixStats::rowSds(expr)
        rsd[rsd == 0] <- 1.0
        expr_norm <- (expr - rm) / rsd
    }

    sExpr <- ServerExpression(expr_norm, colnames(expr), rownames(expr))

    ejson <- toJSON(sExpr, force=TRUE, pretty=TRUE, auto_unbox=TRUE)

    return(ejson)
}

#' Converts row of sigantures score matrix to JSON
#' @importFrom jsonlite toJSON
#' @param ss single-column dataframe with scores for a single signature
#' @return Signature scores list to JSON, with names of each entry that of the list names
sigScoresToJSON <- function(names, values) {

    out <- list(cells = names, values = values)

    json <- toJSON(
                     out,
                     force = TRUE, pretty = TRUE, auto_unbox = TRUE
                     )

    return(json)
}

#' Converts a projection into a JSON object mapping each sample to a projection coordinate.
#' @importFrom jsonlite toJSON
#' @param p Projection coordinate data (NUM_SAMPLES x NUM_COMPONENTS)
#' @return JSON object mapping each sample to a projection coordinate.
coordinatesToJSON <- function(p) {

    coord <- as.data.frame(p)

    # This switching is needed because toJSON will drop row labels
    # if they are integers for some reason
    coord["sample_labels"] <- rownames(coord)
    rownames(coord) <- NULL

    json <- toJSON(coord, force=TRUE, pretty=TRUE,
                   auto_unbox=TRUE, dataframe="values")

    return(json)
}

#' Converts a sigProjMatrix from a FastProject Object to a JSON object
#' @importFrom jsonlite toJSON
#' @param sigzscores Matrix of signature z-scores
#' @param sigpvals Matrix of signature p-values
#' @param sigs Signatures to subset zscores/pvalues
#' @return Subsetted sigProjMatrix converted to JSON
sigProjMatrixToJSON <- function(sigzscores, sigpvals, sigs) {

    sigs <- intersect(sigs, rownames(sigzscores))
    sigpvals <- sigpvals[sigs, , drop = FALSE]

    sigzscores <- sigzscores[rownames(sigpvals), , drop = FALSE]
    sigzscores <- sigzscores[, colnames(sigpvals), drop = FALSE]

    sSPM <- ServerSigProjMatrix(unname(sigzscores), unname(sigpvals), colnames(sigpvals), rownames(sigpvals))

    json <- toJSON(sSPM, force=TRUE, pretty=TRUE)

    return(json)
}

#' convert perason correlation coeffcients between PCs and sgnatures into a JSON object
#' @param pc the pearson correlation coefficients matrix
#' @param sigs the signatures of interest
#' @return Subsetted pearson correlations converted to JSON
pearsonCorrToJSON <- function(pc, sigs) {

    pc <- pc[sigs, ,drop = FALSE]
    cn <- paste("PC", 1:ncol(pc))

    sPC <- ServerSigProjMatrix(unname(pc), unname(pc), cn, sigs)

    json <- toJSON(sPC, force = TRUE, pretty = TRUE)

    return(json)

}

#' Run the analysis again wth user-defined subsets or confguration
#' @param nfp the new FastProject object to analyze
#' @return None
newAnalysis <- function(nfp) {
    saveAndViewResults(analyze(nfp))
}

compressJSONResponse <- function(json, res, req){

    res$set_header("Content-Type", "application/json")

    if (requireNamespace("gzmem", quietly = TRUE) &&
        !is.null(req$get_header("accept_encoding")) &&
        grepl("gzip", req$get_header("accept_encoding"), ignore.case = TRUE)
   ){
        res$set_header("Content-Encoding", "gzip")
        res$body <- gzmem::mem_compress(charToRaw(json), format = "gzip")
    } else {
        res$body <- json
    }
}

#' Lanch the server
#' @importFrom jsonlite fromJSON
#' @importFrom utils browseURL URLdecode stack
#' @param object FastProject object or path to a file containing such an
#' object (saved using saveAndViewResults, or directly using saveRDS)
#' @param port The port on which to serve the output viewer.  If omitted, a
#' random port between 8000 and 9999 is chosen.
#' @param host The host used to serve the output viewer. If omitted, "127.0.0.1"
#' is used.
#' @return None
launchServer <- function(object, port=NULL, host=NULL, browser=TRUE) {

    if (is.null(port)) {
        port <- sample(8000:9999, 1)
    }
    if (is.null(host)) {
        host <- "127.0.0.1"
    }

    # Check for gzmem
    if (!requireNamespace("gzmem", quietly = TRUE)){
        warning("Package 'gzmem' not installed:\n    For faster network communication install gzmem with command: \n    > devtools::install_github(\"hrbrmstr/gzmem\")")
    }

    # Load the static file whitelist
    whitelist_file <- system.file("html_output/whitelist.txt",
                                  package = "VISION")
    static_whitelist <- scan(whitelist_file, what = "",
                             quiet = TRUE)

    url <- paste0("http://", host, ":", port, "/Results.html")
    message(paste("Navigate to", url, "in a browser to interact with the app."))

    if(browser){
        browseURL(url)
    }

    # Launch the server
    jug() %>%
      get("/Signature/Scores/(?<sig_name1>.*)", function(req, res, err) {
        sigMatrix <- object@sigScores
        name <- URLdecode(req$params$sig_name1)
        if (name %in% colnames(sigMatrix)) {
            values <- sigMatrix[, name]
            names <- rownames(sigMatrix)
            out <- sigScoresToJSON(names, values)
            compressJSONResponse(out, res, req)
        } else {
            return("Signature does not exist!")
        }
      }) %>%
      get("/Signature/Meta/(?<sig_name3>.*)", function(req, res, err) {
        metaData <- object@metaData
        name <- URLdecode(req$params$sig_name3)
        if (name %in% colnames(metaData)) {
            names <- rownames(metaData)
            values <- metaData[[name]]
            out <- sigScoresToJSON(names, values)
            compressJSONResponse(out, res, req)
        } else {
            return("Signature does not exist!")
        }
      }) %>%
      get("/Signature/Info/(?<sig_name2>.*)", function(req, res, err){
        signatures <- object@sigData
        name <- URLdecode(req$params$sig_name2)
        out <- "Signature does not exist!"
        if (name %in% names(signatures)) {
          sig <- signatures[[name]]
          out <- signatureToJSON(sig)
        }
        return(out)
      }) %>%
      get("/Signature/Expression/(?<sig_name4>.*)", function(req, res, err) {
        all_names <- vapply(object@sigData, function(x){ return(x@name) }, "")
        name <- URLdecode(req$params$sig_name4)
        index <- match(name, all_names)
        if (is.na(index)){
            return("Signature does not exist!")
        }
        else{
            sig <- object@sigData[[index]]
            genes <- names(sig@sigDict)
            expMat <- object@exprData
            out <- expressionToJSON(expMat, genes, zscore=TRUE)
            compressJSONResponse(out, res, req)
        }
      }) %>%
      get("/FilterGroup/SigClusters/Normal", function(req, res, err) {

        cls <- object@SigConsistencyScores@sigClusters
        cls <- cls$Computed

        out <- toJSON(cls, auto_unbox=TRUE)
        return(out)
      }) %>%
      get("/FilterGroup/SigClusters/Meta", function(req, res, err) {

        cls <- object@SigConsistencyScores@sigClusters
        cls <- cls$Meta

        out <- toJSON(cls, auto_unbox=TRUE)
        return(out)
      }) %>%
      get("/Projections/(?<proj_name1>.*)/coordinates", function(req, res, err) {
        proj <- URLdecode(req$params$proj_name1)
        out <- coordinatesToJSON(object@Projections[[proj]])
        compressJSONResponse(out, res, req)
      }) %>%
      get("/Projections/list", function(req, res, err) {
        proj_names <- names(object@Projections)
        proj_names <- sort(proj_names, decreasing=TRUE) # hack to make tsne on top
        out <- toJSON(proj_names)
        return(out)
      }) %>%
      get("/Tree/Projections/list", function(req, res, err) {
        if (is.null(object@TrajectoryProjections)){
            proj_names <- character()
        } else {
            proj_names <- names(object@TrajectoryProjections)
        }
        out <- toJSON(proj_names)
        return(out)
      }) %>%
      get("/Tree/Projections/(?<proj_name3>.*)/milestones", function(req, res, err) {
        proj <- URLdecode(req$params$proj_name3)

        C <- object@TrajectoryProjections[[proj]]@vData
        W <- object@TrajectoryProjections[[proj]]@adjMat

        out <- list(C, W)

        return(toJSON(out))
      }) %>%
      get("/Tree/Projections/(?<proj_name4>.*)/coordinates", function(req, res, err) {
        proj <- URLdecode(req$params$proj_name4)
        coords <- object@TrajectoryProjections[[proj]]@pData

        out <- coordinatesToJSON(coords)
        compressJSONResponse(out, res, req)

      }) %>%
      get("/Tree/SigProjMatrix/Normal", function(req, res, err) {

        sigs <- colnames(object@sigScores)

        metaData <- object@metaData
        meta_n <- vapply(names(metaData), function(metaName) {
                  is.numeric(metaData[, metaName])
              }, FUN.VALUE = TRUE)

        meta_n <- colnames(metaData)[meta_n]
        sigs <- c(sigs, meta_n)

        out <- sigProjMatrixToJSON(
                                  object@TrajectoryConsistencyScores@sigProjMatrix,
                                  object@TrajectoryConsistencyScores@emp_pMatrix,
                                  sigs)
        return(out)
      }) %>%
      get("/Tree/SigProjMatrix/Meta", function(req, res, err) {

        sigs <- colnames(object@metaData)
        out <- sigProjMatrixToJSON(
                                  object@TrajectoryConsistencyScores@sigProjMatrix,
                                  object@TrajectoryConsistencyScores@emp_pMatrix,
                                  sigs)
        return(out)
      }) %>%
      get("/PCA/Coordinates", function(req, res, err) {

        pc <- object@latentSpace
        out <- coordinatesToJSON(pc)
        compressJSONResponse(out, res, req)

      }) %>%
      get("/PearsonCorr/Normal", function(req, res, err) {

          pc <- object@PCAnnotatorData@pearsonCorr[, 1:10]
          sigs <- rownames(pc)

        return(pearsonCorrToJSON(pc, sigs))
      }) %>%
      get("/PearsonCorr/Meta", function(req, res, err) {

          sigs <- colnames(object@metaData)
          numericMeta <- vapply(sigs,
                                function(x) is.numeric(object@metaData[[x]]),
                                FUN.VALUE = TRUE)
          sigs <- sigs[numericMeta]

          pc <- object@PCAnnotatorData@pearsonCorr[, 1:10]

        return(pearsonCorrToJSON(pc, sigs))
      }) %>%
      get("/PearsonCorr/list", function(req, res, err) {

          pc <- object@PCAnnotatorData@pearsonCorr
          pcnames <- seq(ncol(pc))[1:10]
          result <- toJSON(
                           pcnames,
                           force=TRUE, pretty=TRUE
                           )
          return(result)
      }) %>%
      get("/Expression/Genes/List", function(req, res, err) {

        data <- object@unnormalizedData
        genes <- rownames(data)

        result <- toJSON(
                         genes,
                         force=TRUE, pretty=TRUE
                         )

        compressJSONResponse(result, res, req)

      }) %>%
      get("/Expression/Gene/(?<gene_name2>.*)", function(req, res, err) {

        gene_name <- URLdecode(req$params$gene_name2)
        data <- log2(object@unnormalizedData[gene_name, ] + 1)

        out <- list(cells = names(data), values = data)

        result <- toJSON(
                         out,
                         force = TRUE, pretty = TRUE, auto_unbox = TRUE
                         )

        compressJSONResponse(result, res, req)

      }) %>%
      get("/Clusters/list", function(req, res, err) {
        cluster_vars <- names(object@ClusterSigScores)
        out <- toJSON(cluster_vars,
                      force = TRUE, pretty = TRUE)
        return(out)
      }) %>%
      get("/Clusters/(?<cluster_variable1>.*)/Cells", function(req, res, err) {
        metaData <- object@metaData
        cluster_variable <- URLdecode(req$params$cluster_variable1)
        if (cluster_variable %in% colnames(metaData)) {
            out <- sigScoresToJSON(names = rownames(metaData),
                                            values = metaData[[cluster_variable]])
            compressJSONResponse(out, res, req)
        } else {
            return("No Clusters!")
        }
      }) %>%
      get("/Clusters/(?<cluster_variable2>.*)/SigProjMatrix/Normal", function(req, res, err) {

        sigs <- colnames(object@sigScores)

        metaData <- object@metaData
        meta_n <- vapply(names(metaData), function(metaName) {
                  is.numeric(metaData[, metaName])
              }, FUN.VALUE = TRUE)

        meta_n <- colnames(metaData)[meta_n]
        sigs <- c(sigs, meta_n)

        cluster_variable <- URLdecode(req$params$cluster_variable2)
        pvals <- object@SigConsistencyScores@emp_pMatrix
        zscores <- object@SigConsistencyScores@sigProjMatrix

        cluster_pvals <- object@ClusterSigScores[[cluster_variable]]$pvals
        cluster_zscores <- object@ClusterSigScores[[cluster_variable]]$zscores

        pvals <- pvals[rownames(cluster_pvals), , drop = F]
        zscores <- zscores[rownames(cluster_zscores), , drop = F]

        pvals <- cbind(pvals, cluster_pvals)
        zscores <- cbind(zscores, cluster_zscores)

        out <- sigProjMatrixToJSON(zscores, pvals, sigs)
        return(out)
      }) %>%
      get("/Clusters/(?<cluster_variable3>.*)/SigProjMatrix/Meta", function(req, res, err) {

        sigs <- colnames(object@metaData)

        cluster_variable <- URLdecode(req$params$cluster_variable3)
        pvals <- object@SigConsistencyScores@emp_pMatrix
        zscores <- object@SigConsistencyScores@sigProjMatrix

        cluster_pvals <- object@ClusterSigScores[[cluster_variable]]$pvals
        cluster_zscores <- object@ClusterSigScores[[cluster_variable]]$zscores

        pvals <- pvals[rownames(cluster_pvals), , drop = F]
        zscores <- zscores[rownames(cluster_zscores), , drop = F]

        pvals <- cbind(pvals, cluster_pvals)
        zscores <- cbind(zscores, cluster_zscores)

        out <- sigProjMatrixToJSON(zscores, pvals, sigs)

        return(out)
      }) %>%
      get("/SessionInfo", function(req, res, err) {

        info <- list()

        if (.hasSlot(object, "name") && !is.null(object@name)) {
            info["name"] <- object@name
        } else {
            info["name"] <- ""
        }

        W <- object@latentTrajectory
        hasTree <- !is.null(W)

        info["has_tree"] <- hasTree

        info[["meta_sigs"]] <- colnames(object@metaData)

        info[["pooled"]] <- object@pool

        info[["ncells"]] <- nrow(object@metaData)

        info[["has_sigs"]] <- length(object@sigData) > 0

        result <- toJSON(
                         info,
                         force = TRUE, pretty = TRUE, auto_unbox = TRUE
                         )

        return(result)

     }) %>%
     get("/Cell/(?<cell_id1>.*)/Meta", function(req, res, err) {
         cell_id <- URLdecode(req$params$cell_id1)
         cell_meta <- as.list(object@initialMetaData[cell_id, ])
         out <- toJSON(cell_meta, auto_unbox = TRUE)
         return(out)
     }) %>%
     post("/Cells/Meta", function(req, res, err) {

         subset <- fromJSON(req$body)
         subset <- subset[!is.na(subset)]

         if (object@pool){
             cells <- unname(unlist(object@pools[subset]))
         } else {
             cells <- subset
         }

         metaSubset <- object@initialMetaData[cells, ]

         numericMeta <- vapply(metaSubset, is.numeric, FUN.VALUE = TRUE)

         metaSummaryNumeric <-
             lapply(metaSubset[numericMeta], function(item){
                vals <- quantile(item, probs = c(0, .5, 1), na.rm = TRUE)
                names(vals) <- c("Min", "Median", "Max")
                return(as.list(vals))
             })

         metaSummaryFactor <-
             lapply(metaSubset[!numericMeta], function(item){
                vals <- sort(table(droplevels(item)),
                             decreasing = TRUE)
                vals <- vals / length(item) * 100
                return(as.list(vals))
             })

         metaSummary <- list(numeric = metaSummaryNumeric,
                             factor = metaSummaryFactor
                            )

         out <- toJSON(metaSummary, force=TRUE, pretty=TRUE, auto_unbox=TRUE)
         return(out)

     }) %>%
      post("/Analysis/Run/", function(req, res, err) {
        subset <- fromJSON(req$body)
        subset <- subset[!is.na(subset)]

        if (length(object@pools) > 0) {
            clust <- object@pools[subset]
            subset <- unlist(clust)
        }

        nfp <- createNewFP(object, subset)
        newAnalysis(nfp)
        return()
      }) %>%
      get(path = NULL, function(req, res, err) {

          if (req$path == "/") {
              path <- "Results.html"
          } else {
              path <- substring(req$path, 2) # remove first / character
          }
          path <- paste0("html_output/", path)
          file_index <- match(path, static_whitelist)

          if (is.na(file_index)) {
              res$set_status(404)
              return(NULL)
          }

          file_path <- system.file(static_whitelist[file_index],
                         package = "VISION")

          mime_type <- mime::guess_type(file_path)
          res$content_type(mime_type)

          data <- readBin(file_path, "raw", n = file.info(file_path)$size)

          if (grepl("image|octet|pdf", mime_type)) {
              return(data)
          } else {
              return(rawToChar(data))
          }
      }) %>%
      simple_error_handler_json() %>%
      serve_it(host = host, port = port)
}
