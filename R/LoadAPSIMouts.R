#' Read APSIM .out files.
#' 
#' Reads APSIM .out files.
#' 
#' By default, this function will read in all output files in a directory and 
#' combine them into a single data table. Setting \code{loadAll=FALSE} will read
#' a single file. If the path is omitted it will try to find the file in the current
#' working directory. Constants in outputs will be added as data columns and output 
#' files with differing numbers of columns can also be imported although by 
#' default this will result in an error. Care should be taken when using this 
#' option as a different number of columns in output files usually means the 
#' data came from a different set of reports or simulations which may not be 
#' relevant to your analysis.
#' @param dir (optional) The directory to search for .out files. This is not recursive.
#'   If omitted, the current working directory will be used.
#' @param loadAll If TRUE will load all files in \code{dir}. If FALSE, will load
#'   a single file specified by \code{dir}. Default is TRUE.
#' @param filter A regular expression that matches the files to be loaded.
#'   Default is \code{\\\\.out} which filters for standard apsim output files.
#' @param returnFrame Return the data as a data frame or data table. Default is 
#'   TRUE, FALSE returns a data table.
#' @param n Read the first n files. Good for testing/debugging. Default is 0 
#'   (read all files found).
#' @param fill Where the number or names of columns is not consistent across 
#'   files, fill missing columns with NA. Default is FALSE which will throw an 
#'   error if the columns don't match across all files.
#' @param addConstants Add any constants (such as ApsimVersion, Title or factor 
#'   levels) found as extra columns. Default is TRUE.
#' @param skipEmpty Silently skip empty output files. If false, empty files
#'   will cause an error. Default is FALSE.
#' @export
#' @examples
#' \dontrun{loadApsim("c:/outputs") # load everything in the outputs directory}
#' \dontrun{loadApsim("c:/outputs/simulation.out", loadAll=FALSE) 
#' # load a single file (note extension is required).}
#' \dontrun{loadApsim("c:/outputs", returnFrame=FALSE, fill=TRUE) 
#'   # load everything in the outputs directory, fill any missing columns and return a data table.}
loadApsim <- compiler::cmpfun(function(dir = NULL, loadAll=TRUE, filter = "\\.out", returnFrame = TRUE, n = 0, fill=FALSE, addConstants=TRUE, skipEmpty=FALSE)
{    # this function is precompiled for a 10-12% performance increase
    if (loadAll){ 
        wd <- getwd()
        if(!is.null(dir)){
            setwd(dir)
        }
        else {
            dir <- getwd()
        }
        files <- list.files(pattern = paste(filter, "$", sep="")) # create a list of files
    } else {
        files <- dir
    }
    if (length(files == 0))
        return
    
    allData <- list(NULL)
    fileCount <- 0
    
    for(f in files) {
        print(f)
        if(skipEmpty && file.info(f)$size == 0)
            next
        con <- file(f, open="r")
        count <- 0
        size <- 1
        constants <- NULL
        namesFound <- FALSE
        unitsFound <- FALSE
        
        while (length(oneLine <- readLines(con, n=1, warn=FALSE)) > 0) {
            if(grepl("factors = ", oneLine)){ # line contains a single line factor string
                if(addConstants){
                    oneLine <- stringr::str_replace(oneLine, "factors = ", "")
                    split <- unlist(strsplit(oneLine, ";", fixed="TRUE"), use.names = FALSE)
                    for(s in split) {
                        constants[length(constants) + 1] <- strsplit(s, "=", fixed="TRUE")
                    }
                }
            }else if(grepl("=", oneLine)){ # line contains a constant
                    if(addConstants){
                        constants[length(constants) + 1] <- strsplit(oneLine, " = ", fixed="TRUE")
                    }
                } else {
                    if (!namesFound) { # this line is the column names
                        colNames <- unlist(strsplit(stringr::str_trim(oneLine), " ", fixed=TRUE), use.names = FALSE)
                        colNames <- subset(colNames, colNames != "")
                        namesFound <- TRUE
                    }else if (!unitsFound) { # this line is the units
                        units <- unlist(strsplit(stringr::str_trim(oneLine), " ", fixed=TRUE), use.names = FALSE)
                        units <- subset(units, units != "")
                        # this shouldn't (but can) happen. e.g. (DECIMAL DEGREES) when reporting lat/lon
                        if(length(units) != length(colNames)) stop(paste("Error reading", f, "number of columns does not match number of headings."))
                        unitsFound <- TRUE          
                    } else {    # everything else is data
                        break
                    }
            }
            count <- count + 1
        }
        close(con)
        data <- read.table(f, skip=count, header=FALSE, col.names=colNames, na.strings = c("?", "*"), stringsAsFactors=FALSE) # read the data
        for(c in constants){
            data[[ncol(data) + 1]] <- c[2]
            colNames[length(colNames) + 1] <- c[1]
        }
        colNames <- stringr::str_trim(colNames)
        names(data) <- colNames
        data$fileName <- f
        allData[[length(allData) + 1]] <- data
        fileCount <- fileCount + 1
        if (fileCount == n) break
    }
    allData <- allData[!sapply(allData, is.null)]
    if(returnFrame){
         allData <- as.data.frame(data.table::rbindlist(allData, fill=fill))
    } else {
        allData <- data.table::rbindlist(allData, fill=fill)
      }
    #convert character columns to numeric where possible
    suppressWarnings(for (i in 1:ncol(allData)){
        if(!any(is.na(as.numeric(allData[[i]]))))
            allData[[i]] <- as.numeric(allData[[i]])
    })
    if (loadAll) setwd(wd) #restore wd
    return(allData)
})

#' Extract a token from a vector of strings.
#' 
#' Extract a token from a character vector in a data frame containing a number
#' of delimited tokens. Specialised version of str_split that works on vectors.
#' 
#' By default loadApsim will automatically create columns from constants inside
#' the output files. However sometimes you might want to extract values from 
#' different data such as the file name. This is easy to do if the data is
#' a fixed width, but it can be difficult when it's of variable length and
#' delimited. str_split() is the most common way to deal with this sort of 
#' data, but it doesn't work on a vector.
#' 
#' getToken takes a data frame, a column of type 'character', a seperator and a token position to return
#' each token in the given position. It then appends the token as a new column.
#' @param x A data frame
#' @param cname The name of the column to extract a token from.
#' @param pos The position of the desired token in the token string.
#' @param sep The character to use as a seperator (e.g. ":", ";", etc.) Can be multi-character.
#' @param colName A name for the new column.
getToken <- function(x, cname, pos, sep, colName) {
    if (is.null(cname) | length(cname) != 1)
        stop("cname must be a character vector of length 1.")
    
    delims <- str_count(x[, cname], sep)
    
    if (min(delims) != max(delims))
        stop ("Number of delimiters is not the same in all vector elements.")
    
    m<- str_split_fixed(x[, cname], "_",n= delims + 1)
    
    x <- cbind(x, m[, pos])
    setnames(x, "m[, pos]", colName)
    return(x)
}