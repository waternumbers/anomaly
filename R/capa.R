
.capa.class<-setClass("capa.class",representation(data="matrix",beta="numeric",beta_tilde="numeric",min_seg_len="integer",max_seg_len="integer",max_lag="integer",type="character",
                                                  anomaly_types="integer",anomaly_positions="integer",components="matrix",start_lags="matrix",end_lags="matrix"))
                                                  
capa.class<-function(data,beta,beta_tilde,min_seg_len,max_seg_len,max_lag,type,
                     anomaly_types,anomaly_positions,components,start_lags,end_lags,...)
{
    .capa.class(data=data,beta=beta,beta_tilde=beta_tilde,min_seg_len=min_seg_len,max_seg_len=max_seg_len,max_lag=max_lag,type=type,
                anomaly_types=anomaly_types,anomaly_positions=anomaly_positions,components=components,start_lags=start_lags,end_lags=end_lags,...)
}


#' @name point_anomalies
#' @param object An instance of an S4 class produced by \code{\link{capa}}.
#' @param epoch Positive integer. CAPA methods are sequential and as such, can generate results up to, and including, any epoch within the data series. This can be controlled by the value
#' of \code{epoch} and is useful for examining how the inferred anomalies are modified as the data series grows. The default value for \code{epoch} is the length of the data series.
#' 
#' @return A data frame. 
#' @include generics.R
#' @rdname point_anomaly-methods
#'
#' @aliases point_anomalies,capa.class-method
#'
#' @export
setMethod("point_anomalies",signature=list("capa.class"),
          function(object,epoch=nrow(object@data)){
              ## check epoch is valid
              epoch <- int_in_range(epoch,1,nrow(object@data))
              
              # get the anomalies
              anoms<-anomalies(object,epoch)

              X <- object@data
              
              
              p_anoms<-Map(function(x) x[1],Filter(function(x) x[1] == x[2],anoms))
              if(length(p_anoms) > 0)
              {
                  p_anom_daf <- Reduce(rbind,
                       Map(
                         function(p_anom)
                         {
                           variates<-seq(1,ncol(X))[as.logical(object@components[p_anom[1],])]
                           location<-rep(p_anom[1],length(variates))
                           strength<-abs(X[p_anom[1],variates])
                           return(
                             data.frame("location"=location,
                                        "variate"=variates,
                                        "strength"=strength)
                           )
                         },
                         p_anoms)
                  )
              }
              
              extra_anoms <- data.frame("location"=integer(0),"variate"=integer(0),"strength"=integer(0))
              
              if (object@type == "robustmean"){
                
                tmp <- collective_anomalies(as(object,"capa.class"))
                
                if (nrow(tmp)>0)
                {
                  
                  extra_anoms <- Reduce(rbind,
                                      Map(
                                        function(ii)
                                        {
                                          relevant_row = tmp[ii,]
                                          if (is.null(relevant_row$start.lag)){
                                            effective_start = relevant_row$start
                                            effective_end   = relevant_row$end
                                          } else{
                                            effective_start = relevant_row$start+relevant_row$start.lag
                                            effective_end   = relevant_row$end-relevant_row$start.lag                                      
                                          }
                                          x_data = X[effective_start:effective_end,relevant_row$variate]
                                          standardised_x_data = x_data - tukey_mean(x_data,sqrt(object@beta_tilde))
                                          
                                          location<-which(abs(standardised_x_data)>sqrt(object@beta_tilde))
                                          strength<-abs(standardised_x_data[location])
                                          variates<-rep(relevant_row$variate,length(location))
                                          if (length(location > 0)){
                                            location = location - 1 + effective_start
                                          }
                                          return(
                                            data.frame("location"=location,
                                                       "variate"=variates,
                                                       "strength"=strength)
                                          )
                                        },
                                        1:nrow(tmp))
                  )
                  
                }
              
              }
              
              if(length(p_anoms) + nrow(extra_anoms) == 0)
              {
                  return(data.frame("location"=integer(0),"variate"=integer(0),"strength"=integer(0)))
              }
              else
              {
                  out <- rbind(p_anom_daf,extra_anoms)
                  return(out[order(out$location,out$variate),])
              }
          }
          )




# helper for collective_anomaies with object of type capa.class
merge_collective_anomalies<-function(object,epoch)
{
   if(object@type != "mean")
    {
        stop("merge=TRUE option only available when type=mean")
    }
   canoms<-collective_anomalies(object,merged=FALSE)
   # get the location (start,end) for each collective anomaly
   locations<-unique(canoms[,1:2])
   # get the sum of the test statistic over the variates affected by each collective anomaly
   sums<-unlist(Map(function(start) sum(canoms[canoms[,1] == start,]$mean.change),locations[,1]))
   # order the locations
   locations<-locations[order(sums,decreasing=TRUE),]
   # sort the sums
   sums<-sort(sums,decreasing=TRUE)
   # divide sums by the sum of the betas
   sums<-sums/sum(object@beta)
   return(data.frame("start"=locations[,1],"end"=locations[,2],"mean.change"=sums))
}




#' @name collective_anomalies
#' @param object An instance of an S4 class produced by \code{\link{capa}}.
#' @param epoch Positive integer. CAPA methods are sequential and as such, can generate results up to, and including, any epoch within the data series. This can be controlled by the value
#' of \code{epoch} and is useful for examining how the inferred anomalies are modified as the data series grows. The default value for \code{epoch} is the length of the data series.
#' @param merged Boolean value. If \code{merged=TRUE} then collective anomalies that are common across multiple variates are merged together. This is useful when comparing the relative strength
#' of multivariate collective anomalies. Default value is \code{merged=FALSE}. Note - \code{merged=TRUE} is currently only available when \code{type="mean"}.  
#' 
#' @return A data frame.
#' @include generics.R
#' @rdname collective_anomalies-methods
#'
#' @aliases collective_anomalies,capa.class-method
#' 
#' @seealso \code{\link{capa}},\code{\link{pass}},\code{\link{sampler}}. 
#'
#' @export
setMethod("collective_anomalies",signature=list("capa.class"),
          function(object,epoch=nrow(object@data),merged=FALSE)
          {
              if(epoch < 0)
              {
                  stop("epoch should be a positive integer")
              }
              if(epoch > nrow(object@data))
              {
                  stop("epoch cannot be greater than the number of observations in the data")
              }
              if(merged)
              {
                  return(merge_collective_anomalies(object,epoch))
              }
              # get the anomalies
              anoms<-anomalies(object,epoch)
              # transform data
              X<-object@data
              c_anoms<-Filter(function(x) x[1] != x[2],anoms)
              if(length(c_anoms) == 0)
              {                      
                  return(data.frame("start"=integer(0),"end"=integer(0),"variate"=integer(0),"start.lag"=integer(0),"end.lag"=integer(0),"mean.change"=integer(0),"variance.change" = integer(0)))
              }
              res<-Reduce(rbind,
                          Map(
                              function(c_anom)
                              {
                                  variates<-seq(1,ncol(X))[as.logical(object@components[c_anom[2],])]
                                  start<-rep(c_anom[1],length(variates))
                                  end<-rep(c_anom[2],length(variates))
                                  start_lags<-object@start_lags[c_anom[2],variates]
                                  end_lags<-object@end_lags[c_anom[2],variates]
                                  return(
                                      data.frame("start"=start,
                                                 "end"=end,
                                                 "variate"=variates,
                                                 "start.lag"=start_lags,
                                                 "end.lag"=end_lags)
                                  )
                              },
                              c_anoms)
                          )
              if(object@type == "meanvar")
              {
                  changes<-data.frame(
                      Reduce(rbind,
                             Map(
                                 function(variate,start,end,start_lag,end_lag)
                                 {
                                     variance<-var(X[(start+start_lag):(end-end_lag),variate])
                                     variance_change<-sqrt(variance)+1/sqrt(variance)-2
                                     mean_change<-mean(X[(start+start_lag):(end-end_lag),variate])^2/sqrt(variance)
                                     return(array(c(mean_change,variance_change),c(1,2)))    
                                 },
                                 res$variate,
                                 res$start,
                                 res$end,
                                 res$start.lag,
                                 res$end.lag)
                             ),row.names=NULL
                  )
                  names(changes)<-c("mean.change","variance.change")
              }
              else if(object@type %in% c("mean","robustmean"))
              {
                  changes<-data.frame(
                      Reduce(rbind,
                             Map(
                                 function(variate,start,end,start_lag,end_lag)
                                 {
                                     if (object@type == "mean"){
                                          mean_change<-mean(X[(start+start_lag):(end-end_lag),variate])^2
                                     }
                                     if (object@type == "robustmean"){
                                          mean_change<-tukey_mean(X[(start+start_lag):(end-end_lag),variate],sqrt(object@beta_tilde))^2
                                     }
                                     variance_change<-mean_change*((end-end_lag)-(start+start_lag)+1) 
                                     return(array(c(mean_change,variance_change),c(1,2)))
                                     # return(array(c(mean_change),c(1,1)))    
                                 },
                                 res$variate,
                                 res$start,
                                 res$end,
                                 res$start.lag,
                                 res$end.lag)
                             ),row.names=NULL
                  )
                  names(changes)<-c("mean.change","test.statistic")
                  # names(changes)<-c("mean.change")
              }
              else
              {
                  # default - no summary information produced
                  return(res)
              }
              res<-cbind(res,changes);
              ## tighten
              
              res <- do.call(rbind,
                             lapply(split(res,res$start),
                                    function(d){
                                        d$end.lag <- d$end.lag-min(d$end.lag)
                                        d$start.lag <- d$start.lag-min(d$start.lag)
                                        return(d)
                                    }))
              
	      ## start.lag<-end.lag<-"."<-"%<>%"<-NULL # circumvent CRAN check issues
	      ## res %<>% group_by(.,start) %>% mutate(.,end.lag=end.lag-min(end.lag),start.lag=start.lag-min(start.lag)) %>% as.data.frame(.)
              return(res)
          }
          )







#' Summary of collective and point anomalies.
#'
#' @name summary
#'
#' @description Summary methods for S4 objects returned by \code{\link{capa}}, 
#' \code{\link{pass}}, and \code{\link{sampler}}.  The output displayed
#' depends on the type of object passed to summary. For all types, the output indicates whether the data is univariate or
#' multivariate, the number of observations in the data, and the type of change being detected.
#'
#' @docType methods
#'
#' @param object An instance of an S4 class produced by \code{\link{capa}} or \code{\link{pass}}.
#' @param epoch Positive integer. CAPA methods are sequential and as such, can generate results up to, and including, any epoch within the data series. This can be controlled by the value
#' of \code{epoch} and is useful for examining how the inferred anomalies are modified as the data series grows. The default value for \code{epoch} is the length of the data series.
#' @param ... Ignored.
#'
#' @rdname summary-methods
#'
#' @aliases summary,capa.class-method
#' 
#' @seealso \code{\link{capa}}, \code{\link{pass}},\code{\link{sampler}}. 
#'
#' @export
setMethod("summary",signature=list("capa.class"),function(object,epoch=nrow(object@data))
{
  summary_show_common(object,epoch)
  p_anoms<-point_anomalies(object,epoch)
  c_anoms<-collective_anomalies(object,epoch)
  cat("\n",sep="")
  cat("Point anomalies detected : ",nrow(p_anoms),"\n",sep="")
  if (nrow(p_anoms)>0)
  {
     print(p_anoms)
  }
  cat("\n",sep="")
  cat("Collective anomalies detected : ",length(unique(c_anoms$start)),"\n",sep="")
  if (nrow(c_anoms)>0)
  {
    print(c_anoms)
  }
  invisible()
})



#' Displays S4 objects produced by capa methods.
#'
#' @name show
#'
#' @description Displays S4 object produced by \code{\link{capa}}, \code{\link{pass}}, \code{\link{bard}}, and \code{\link{sampler}}.
#' The output displayed depends on the type of S4 object passed to the method. For all types, the output indicates whether the data is univariate or
#' multivariate, the number of observations in the data, and the type of change being detected.
#'
#' @docType methods
#'
#' @param object An instance of an S4 class produced by \code{\link{capa}}, \code{\link{pass}}, \code{\link{bard}}, or \code{\link{sampler}}.
#'
#' @rdname show-methods
#'
#' @aliases show,capa.class-method
#' 
#' @seealso \code{\link{capa}},\code{\link{pass}},\code{\link{bard}},\code{\link{sampler}}. 
#'
#' @export
setMethod("show",signature=list("capa.class"),function(object)
{
    summary_show_common(object)
    p_anoms<-point_anomalies(object)
    c_anoms<-collective_anomalies(object)
    cat("Point anomalies detected : ",nrow(p_anoms),"\n",sep="")
    cat("Collective anomalies detected : ",length(unique(c_anoms$start)),"\n",sep="")
    invisible()
})


anomalies<-function(x,epoch=NULL)
{
    anomaly_types<-x@anomaly_types
    anomaly_positions<-x@anomaly_positions
    if(is.null(epoch))
    {
        epoch<-length(anomaly_types) 
    }
    if(epoch < 0 || epoch > length(anomaly_types))
    {
	stop("epoch must be a positive integer <= number of observations in data")
    }
    anomaly_types<-anomaly_types[1:epoch]
    anomaly_positions<-anomaly_positions[1:epoch]
    anom<-list()
    cursor<-length(anomaly_positions)
    count<-0
    while(cursor > 1)
    {
        if(anomaly_types[cursor] == 1)
        {
            count<-count+1
            anom[[count]]<-c(cursor,cursor)
        }
        if(anomaly_types[cursor] == 2)
        {
            count<-count+1
            anom[[count]]<-c(anomaly_positions[cursor]+1,cursor)
        }
        cursor<-anomaly_positions[cursor]
    }
    return(rev(anom))
}




## NOT EXPORTED - helper function for computing beta
compute_beta <- function(beta,type,n,p,max_lag,max_seg_len,min_seg_len){
    ## populate if null
    if(is.null(beta)){
        s <- 1.5*log(n)
        if(type %in% c("mean","robustmean")){
            if (max_lag == 0){
                
                a_vector <- qchisq(seq(p-1,0)/p, 1)
                tmp <- 2*(s+log(p)) + 1:p + 2*p*a_vector*dchisq(a_vector, 1) +
                    2*sqrt((1:p+2*p*a_vector*dchisq(a_vector, 1))*(s+log(p)))
                tmp[p] <- 2*(s+log(p)) + p + 2*sqrt(p*(s+log(p)))
                beta <- pmin(2*s + 2*(1:p)*log(p),
                             rep(p + 2*s + 2*sqrt(p*s),p),
                             tmp)
                beta <- diff( c(0,beta) )
            }else{
                beta <- rep(2*log(p*(max_lag+1)),p)
                beta[1] <- beta[1] + 2*s
            }
        }
        if(type == "meanvar")
        {
            beta <- rep(4*log(p*(max_lag+1)),p)
            beta[1] <- beta[1] + 4*s
            if(p==1){ beta <- beta /1.5 } ## TODO this matches old code bu seems odd is s set wrong??
        }
    }
    ## scale to correct dim for C code....
    if(length(beta) == 1){ beta <- rep(beta,p) }
    if( (p==1) & length(beta)==1 ){ ## this allows for different penalisation of diffeent lengths in univariate case
        p <- c(1,max_seg_len - min_seg_len + 1)
        beta <- rep(beta,p[2])
    }

    ## check properties
    if(!(length(beta) %in% p) || !all(is.finite(beta)) || !all(beta>=0) ){
        stop( paste("beta should be a numeric vector >=0 of length",paste(p,collapse=" or ")) )
    }
   
    return(beta)
}


    

## # not exported - helper function used by capa function
## capa.mv_call<-function(x,beta,beta_tilde,type,min_seg_len,max_seg_len,max_lag)
## {
    
##     ## configure defaults as required
##     marshaller <- switch(type,
##                          "meanvar" = marshall_MeanVarAnomalyMV,
##                          "mean" = marshall_MeanAnomalyMV,
##                          "robustmean" = marshall_RobustMeanAnomalyMV,
##                          stop("Unknown type"))
    
##     beta <- compute_beta(beta,type,nrow(x),ncol(x),max_lag,max_seg_len,min_seg_len)                                                       ## THE code below is left in aid checking compute_beta             
##     ## }
##     ## # process beta
##     ## n <- nrow(x)
##     ## p <- ncol(x)
##     ## s <- 1.5*log(n)
##     ## if (is.null(beta))
##     ## {            
##     ##     if(type %in% c("mean","robustmean"))
##     ##     {
##     ##         if (max_lag == 0)
##     ##         {
##     ##             to_be_tried <- 1:p
##     ##             a_vector <- qchisq(seq(p-1,0)/p, 1)
        
##     ##             penalty_1 <- 2*s + 2*to_be_tried*log(p)
##     ##             penalty_2 <- rep(p + 2*s + 2*sqrt(p*s),p)
        
##     ##             penalty_3    <- 2*(s+log(p)) + 1:p + 2*p*a_vector*dchisq(a_vector, 1) + 2*sqrt((1:p+2*p*a_vector*dchisq(a_vector, 1))*(s+log(p)))
##     ##             penalty_3[p] <- 2*(s+log(p)) + p + 2*sqrt(p*(s+log(p)))
        
##     ##             beta <- diff( c(0,pmin(penalty_1,penalty_2,penalty_3)))   
##     ##         }
      
##     ##         if (max_lag > 0)
##     ##         {
##     ##             beta <- rep(2*log(p*(max_lag+1)),p)
##     ##             beta[1] <- beta[1] + 2*s
##     ##         }
##     ##     }
##     ##     if(type == "meanvar")
##     ##     {
##     ##         beta <- rep(4*log(p*(max_lag+1)),p)
##     ##         beta[1] <- beta[1] + 4*s         
##     ##     }
##     ## }
##     ## else if(length(beta) == 1)
##     ## {
##     ##     beta <- rep(beta,p)
##     ## }
##     ## if(is.null(beta_tilde))
##     ## {
##     ##     beta_tilde <- 3*log(length(x))
##     ## }
    
##     # call the underlying method
##     S<-marshaller(as.vector(x),
##                   as.integer(nrow(x)),
##                   as.integer(ncol(x)),
##                   as.integer(max_lag),
##                   as.integer(min_seg_len),
##                   beta,
##                   beta_tilde,
##                   as.integer(max_seg_len),
##                   as.integer(1))
##     # construct the S4 capa class instance
##     S <- matrix(S,nrow(x),byrow=T)
##     p <- ncol(x)
##     return(
##         capa.class(x,
##                    array(beta,c(length(beta),1)),
##                    array(beta_tilde,c(1,1)),
##                    as.integer(min_seg_len),
##                    as.integer(max_seg_len),
##                    integer(max_lag),
##                    type,
##                    function() return(),
##                    S[,1], 
##                    S[,2],
##                    matrix(S[,2 + 0*p + 1:p],ncol=p),
##                    matrix(S[,2 + 1*p + 1:p],ncol=p),  
##                    matrix(S[,2 + 2*p + 1:p],ncol=p))
##         )
## }


## # not exported - helper function for capa function
## capa.uv_call<-function(x,beta,beta_tilde,type,min_seg_len,max_seg_len)
## {
##     ## configure defaults as required
##     marshaller <- switch(type,
##                          "meanvar" = marshall_MeanVarAnomaly,
##                          "mean" = marshall_MeanAnomaly,
##                          "robustmean" = marshall_RobustMeanAnomaly,
##                          stop("Unknown type"))
##     beta <- compute_beta(beta,type,nrow(x),ncol(x),0,max_seg_len,min_seg_len)
##     ## THE code below is left in aid checking compute_beta 
##     ## if(is.null(beta))
##     ## {
##     ##     if(type %in% c("mean","robustmean"))
##     ##     {
##     ##         beta <- 3*log(length(x))
##     ##     }
##     ##     else 
##     ##     {
##     ##         beta <- 4*log(length(x))
##     ##     }
##     ## }
##     ## if(length(beta) > 1 & length(beta) != (max_seg_len - min_seg_len + 1))
##     ## {
##     ##     warning("beta has a number of entries larger than 1 but not equal to max_seg_len - min_seg_len + 1. Only the first one is kept.")
##     ##     beta <- beta[1]
##     ## }
##     ## if(length(beta) == 1)
##     ## {
##     ##     beta <- rep(beta,max_seg_len - min_seg_len + 1)
##     ## }
##     ## if(is.null(beta_tilde))
##     ## {
##     ##     beta_tilde <- 3*log(length(x))
##     ## }
##     S<-marshaller(x,
##                   as.integer(length(x)),
##                   as.integer(min_seg_len),
##                   as.integer(max_seg_len),
##                   beta,
##                   beta_tilde,
##                   as.integer(1))
## 		     blob<-list(x,
##                as.integer(length(x)),
##                as.integer(min_seg_len),
##                as.integer(max_seg_len),
##                beta,
##                beta_tilde,
##                as.integer(1),
## 	       S)	       
##     # construct the S4 capa class instance
##     return(
## 	capa.class(array(x,c(length(x),1)), 
## 		     array(beta,c(length(beta),1)),
##                      array(beta_tilde,c(1,1)),
##                      as.integer(min_seg_len),
##                      as.integer(max_seg_len),
##                      integer(),
##                      type,
##                      function() return(),
##                      S[seq(1,length(S),2)],
##                      S[seq(2,length(S),2)],
##                      array(1,c(length(x),1)), 
##                      array(0,c(length(x),1)), 
##                      array(0,c(length(x),1))) 
##         )
## }


#' A technique for detecting anomalous segments and points based on CAPA.
#'
#' @name capa 
#'
#' @description A technique for detecting anomalous segments and points based on CAPA (Collective And Point Anomalies) by Fisch et al. (2022).
#' This is a generic method that can be used for both univariate and multivariate data. The specific method that is used for the analysis is deduced by \code{capa} from the dimensions of the data.
#' The inputted data is either a vector (in the case of a univariate time-series) or a array with p columns (if the the time-series is p-dimensional). The CAPA procedure assumes that each component
#' of the time-series is standardised so that the non-anomalous segments of each component have mean 0 and variance 1. This may require pre-processing/standardising.
#' For example, using the median of each component as a robust estimate of its mean, and the mad (median absolute deviation from the median) estimator to get a robust estimate of the variance.
#' 
#' @param x A numeric matrix with n rows and p columns containing the data which is to be inspected. The time series data classes ts, xts, and zoo are also supported.  
#' @param beta A numeric vector of length p giving the marginal penalties. If beta is missing and p == 1 then beta = 3log(n) when the type is "mean" or "robustmean", and beta = 4log(n) otherwise.
#' If beta is missing and p > 1, type ="meanvar" or type = "mean" and max_lag > 0 then it defaults to the penalty
#' regime 2' described in Fisch, Eckley and Fearnhead (2022). If beta is missing and p > 1, type = "mean"/"meanvar" and max_lag = 0 it defaults to the pointwise minimum of the penalty regimes
#' 1, 2, and 3 in Fisch, Eckley and Fearnhead (2022).
#' @param beta_tilde A numeric constant indicating the penalty for adding an additional point anomaly. If beta_tilda is missing it defaults to 3log(np), where n and p are the data dimensions.
#' @param type A string indicating which type of deviations from the baseline are considered. Can be "meanvar" (default) for collective anomalies characterised by joint changes in mean and
#' variance (the default), "mean" for collective anomalies characterised by changes in mean only, or "robustmean" (only allowed when p = 1) for collective anomalies characterised by changes in mean only which can be polluted by outliers.
#' @param min_seg_len An integer indicating the minimum length of epidemic changes. It must be at least 2 and defaults to 10.
#' @param max_seg_len An integer indicating the maximum length of epidemic changes. It must be at least min_seg_len and defaults to Inf.
#' @param max_lag A non-negative integer indicating the maximum start or end lag. Only useful for multivariate data. Default value is 0.
#' 
#' @return An instance of an S4 class of type capa.class. 
#'
#' @references \insertRef{2018arXiv180601947F}{anomaly}
#'
#'
#' @examples
#' library(anomaly)
#' # generate some multivariate data
#' data(simulated)
#' res<-capa(sim.data,type="mean",min_seg_len=2,max_lag=5)
#' collective_anomalies(res)
#' plot(res)
#' 
#' @export
#'
capa<-function(x,beta,beta_tilde,type=c("meanvar","mean","robustmean"),min_seg_len=10,max_seg_len=Inf,max_lag=0)
{
    # process missing values
    if(missing(beta))
    {
       beta <- NULL
    }
    if(missing(beta_tilde))
    {
       beta_tilde <- NULL
    }    

    # data needs to be in the form of an array
    x<-to_array(x)

    ## check the type 
    type <- match.arg(type)
       
    ## check max_lag
    max_lag <- int_in_range(max_lag,0,nrow(x),"max_lag")
    if( (ncol(x)==1) & (max_lag != 0)){
        warning("max_lag != 0 redundant for a univariate analysis")
        max_lag <- 0 ## since used in later code
    }

    ## check min_seg_len
    min_seg_len <- switch(type,
                          "mean" = int_in_range(min_seg_len,lwr=1,upr=nrow(x),lbl="min_seg_len"),
                          "robustmean" = int_in_range(min_seg_len,lwr=1,upr=nrow(x),lbl="min_seg_len"),
                          "meanvar" = int_in_range(min_seg_len,lwr=2,upr=nrow(x),lbl="min_seg_len"),
                          stop("unknown type"))
    
    ## check max_seg_len
    if(max_seg_len == Inf){ max_seg_len = nrow(x) }
    max_seg_len <- int_in_range(max_seg_len,lwr=min_seg_len,upr=nrow(x),lbl="max_seg_len")
    
    ## check beta_tilde - penalisation of point anomaly
    if(is.null(beta_tilde)){ beta_tilde <- 3*log(length(x)) } ## TODO - check same in uni and multivarite cases..
    
    if( !(length(beta_tilde)==1) || !is.finite(beta_tilde) || (beta_tilde < 0) ){
        stop("beta_tilde must be numeric value >= 0")
    }
    
    ## check beta
    beta <- compute_beta(beta,type,nrow(x),ncol(x),max_lag,max_seg_len,min_seg_len)

    ## work out what we are calling and call it
    ## TODO tidy up when the C code is checked /rewritten
    if(ncol(x)==1){
        marshaller <- switch(type,
                             "meanvar" = marshall_MeanVarAnomaly,
                             "mean" = marshall_MeanAnomaly,
                             "robustmean" = marshall_RobustMeanAnomaly,
                             stop("Unknown type"))
        S <- marshaller(as.vector(x),
                        nrow(x),
                        min_seg_len,
                        max_seg_len,
                        beta,
                        beta_tilde,
                        as.integer(1))
        out <- capa.class(x,
                          beta,
                          beta_tilde,
                          min_seg_len,
                          max_seg_len,
                          max_lag,
                          type,
                          S[seq(1,length(S),2)],
                          S[seq(2,length(S),2)],
                          matrix(1,nrow(x)),
                          matrix(0,nrow(x)),
                          matrix(0,nrow(x))
                          )
    }else{
        ## configure defaults as required
        marshaller <- switch(type,
                             "meanvar" = marshall_MeanVarAnomalyMV,
                             "mean" = marshall_MeanAnomalyMV,
                             "robustmean" = marshall_RobustMeanAnomalyMV,
                             stop("Unknown type"))
        # call the underlying method
        S<-marshaller(as.vector(x),
                      nrow(x),
                      ncol(x),
                      max_lag,
                      min_seg_len,
                      beta,
                      beta_tilde,
                      max_seg_len,
                      as.integer(1))
        ## construct the S4 capa class instance
        S <- matrix(S,nrow(x),byrow=T)
        p <- ncol(x)
        out <- capa.class(x,
                          beta,
                          beta_tilde,
                          min_seg_len,
                          max_seg_len,
                          max_lag,
                          type,
                          S[,1], 
                          S[,2],
                          S[,2 + 0*p + 1:p],
                          S[,2 + 1*p + 1:p],  
                          S[,2 + 2*p + 1:p])
    }
    out@data<-x ## TODO - not sure why this is here - x already passed to the class????
    return(out)
}



##     # call appropriate helper function
##     tryCatch(
##     {
##         if(ncol(x)==1)
##         {
##             res<-capa.uv_call(x,beta,beta_tilde,type,min_seg_len,max_seg_len)
##             res@data<-x
##             return(res)
##         }
##         else
##         {
##             res<-capa.mv_call(x,beta,beta_tilde,type,min_seg_len,max_seg_len,max_lag)
##             res@data<-x
##             return(res)
##         }
##     },error = function(e) {print(e$message);stop();})

    
## }


capa_line_plot <- function(object,variate_names, epoch, subset)
{
    
    X <- object@data
    X <- X[,subset,drop=FALSE]

    if( length(colnames(X)) != ncol(X) ){ variate_names <- FALSE }
    
    if(!variate_names){ colnames(X) <- paste(subset) }

    nms <- colnames(X)
    
    
    X <- data.frame(x = rep(1:nrow(X),ncol(X)),
                          variable = rep(colnames(X),each=nrow(X)),
                          value = as.numeric(X))
    
    ##data_df$x <- 1:nrow(data_df)
    ##data_df <- tidyr::gather(data_df,variable,value,-x) ## TODO replace this
    

    out <- ggplot(X,aes(x=.data$x,y=.data$value)) + geom_point(alpha=0.3)

    ## highlight the collective anomalies
    c_anoms <- collective_anomalies(object,epoch=epoch)
    c_anoms <- c_anoms[c_anoms$variate %in% subset,]
    
    if( nrow(c_anoms) > 0 ){
        c_anoms$variable<-nms[c_anoms$variate]
        c_anoms$ymin <- -Inf
        c_anoms$ymax <- Inf
        c_anoms$start_with_lag <- c_anoms$start + c_anoms$start.lag
        c_anoms$end_with_lag <- c_anoms$end - c_anoms$end.lag
        out <- out + geom_rect(data=c_anoms,inherit.aes = FALSE,
                               mapping=aes(xmin = .data$start, xmax = .data$end, ymin = .data$ymin, ymax = .data$ymax),
                               fill="blue",alpha=0.2)
        out <- out + geom_rect(data=c_anoms,inherit.aes = FALSE,
                               mapping=aes(xmin = .data$start_with_lag,xmax = .data$end_with_lag, ymin = .data$ymin,ymax = .data$ymax),
                               fill="blue",alpha=0.5)
    }
    
    # highlight the point anomalies
    p_anoms<-point_anomalies(object,epoch)
    p_anoms<-p_anoms[p_anoms$variate %in% subset,]
    
    if(nrow(p_anoms) > 0){
        p_anoms_df <- do.call(rbind,
                              Map(function(a,b) X[X$variate==a & X$x==b,],
                                  p_anoms$variate,p_anoms$location))
        
        out <- out + geom_point(data=p_anoms_df,colour="red", size=1.5,alpha=0.3)
    }

    # grey out the data after epoch
    if(epoch != nrow(object@data)){
        d <- data.frame(variable=nms[subset],x1=epoch,x2=nrow(object@data),y1=-Inf,y2=Inf)	
        out <- out + geom_rect(data=d,inherit.aes=F,
                               mapping=aes(xmin=.data$x1,xmax=.data$x2,ymin=.data$y1,ymax=.data$y2),fill="yellow",alpha=0.2)
    }

    ## rest of layout
    out <- out + facet_grid(.data$variable~., scales="free_y") #factor(variable, levels = names(data_df)),scales="free_y")
    out <- out + theme_bw() + theme(axis.text.y=element_blank()) + labs(x="t")
    if(variate_names==FALSE){
        out<-out+theme(strip.text.y=element_blank())
    }
    return(out)
}


capa_tile_plot<-function(object,variate_names,epoch,subset){
    # nulling out variables used in ggplot to get the package past CRAN checks
    ## x1<-y1<-x2<-y2<-variable<-value<-NULL
    ##df<-as.data.frame(object@data)
    ## df<-as.data.frame(df[,rev(subset),drop=FALSE])
    X <- object@data[,rev(subset),drop=FALSE]
    
    if( length(colnames(X)) != ncol(X) ){ variate_names <- FALSE }
    if(!variate_names){ colnames(X) <- paste( rev(subset) ) }

    ## normalise data
    X <- apply(X,2,function(x){ (x-min(x))/(max(x)-min(x)) })
    ## for(i in 1:ncol(df))
    ## {
    ##     df[,i]<-(df[,i]-min(df[,i]))/(max(df[,i])-min(df[,i]))
    ## }
    
    ## t<-data.frame("t"=seq(1,nrow(df)))
    ## molten.data<-gather(cbind(t,df),variable,value,-t)
    molten.data <- data.frame(t = rep(1:nrow(X),ncol(X)),
                              variable = rep(colnames(X),each=nrow(X)),
                              value = as.numeric(X)) ##unlist(df))

    out<-ggplot(molten.data, aes(x = .data$t, .data$variable))
    out<-out+geom_tile(aes(fill=.data$value))
    # get any collective anomalies
    c_anoms<-collective_anomalies(object,epoch=epoch)
    c_anoms<-c_anoms[c_anoms$variate %in% subset,]
    c_anoms<-unique(c_anoms[,1:2])
    if(!any(is.na(c_anoms)) & nrow(c_anoms) > 0)
    {
        ymin<-0
        ymax<-ncol(X)
        out<-out+annotate("rect",xmin=c_anoms$start,xmax=c_anoms$end,ymin=ymin,ymax=ymax+1,alpha=0.0,color="red",fill="yellow")
    }
    if(epoch != nrow(object@data))
        {
            d<-data.frame(x1=epoch,x2=nrow(object@data),y1=-Inf,y2=Inf)
            out<-out+geom_rect(data=d,inherit.aes=F,mapping=aes(xmin=.data$x1,xmax=.data$x2,ymin=.data$y1,ymax=.data$y2),
                               fill="yellow",alpha=0.2)
        }

    out<-out+theme_bw()
    out<-out+theme(axis.text.y=element_blank())
    out<-out+theme(axis.ticks.y=element_blank())
    out<-out+theme(panel.grid.major = element_blank(),panel.grid.minor = element_blank())


    return(out)
}


#' Visualisation of data, collective and point anomalies.
#'
#' @description Plot methods for S4 objects returned by \code{\link{capa}}, \code{\link{pass}}, and \code{\link{sampler}}. 
#'
#' The plot can either be a line plot or a tile plot, the type produced depending on the options provided to the \code{plot} function and/or the dimensions of the
#' data associated with the S4 object.
#'
#' @docType methods
#'
#' @param x An instance of an S4 class produced by \code{\link{capa}}, \code{\link{pass}}, or \code{\link{sampler}}. 
#' @param subset A numeric vector specifying a subset of the variates to be displayed. Default value is all of the variates present in the data.
#' @param variate_names Logical value indicating if variate names should be displayed on the plot. This is useful when a large number of variates are being displayed
#' as it makes the visualisation easier to interpret. Default value is FALSE.
#' @param tile_plot Logical value. If TRUE then a tile plot of the data is produced. The data displayed in the tile plot is normalised to values in [0,1] for each variate. A tile plot is always produced if there are more then 20 variates selected
#' This type of plot is useful when the data contains are large number of variates. The default value is TRUE if the number of variates is greater than 20.
#' @param epoch Positive integer. CAPA methods are sequential and as such, can generate results up to, and including, any epoch within the data series. This can be controlled by the value
#' of \code{epoch} and is useful for examining how the inferred anomalies are modified as the data series grows. The default value for \code{epoch} is the length of the data series.
#' 
#' @return A ggplot object.
#'
#' @rdname plot-methods
#'
#' @aliases plot,capa.class
#' 
#' @seealso \code{\link{capa}},\code{\link{pass}},\code{\link{sampler}}.
#'
#' @export 
setMethod("plot",signature=list("capa.class"),function(x,subset,variate_names=FALSE,tile_plot=FALSE,epoch=nrow(x@data))
{
    
    if(missing(subset)){ subset<-1:ncol(x@data) }

    epoch <- int_in_range(epoch,1,nrow(x@data),"epoch")
    

    ## if(epoch < 0)
    ## {
    ##     stop("epoch should be a positive integer")
    ## }
    ## if(epoch > nrow(x@data))
    ## {
    ##     stop("epoch cannot be greater than the number of observations in the data")
    ## }

    subset <- sort(unique(as.integer(subset)))
    if( !all(subset>0 & subset<=ncol(x@data)) ){ stop(paste("subset values should be between 1 and", ncol(x@data))) }

    variate_names <- as.logical(variate_names)
    if(is.na(variate_names)){ stop("variate_names should be a logical") }
    
    tile_plot <- as.logical(tile_plot)
    if(is.na(tile_plot)){ stop("tile_plot should be a logical") }

    if(length(subset) > 20){ tile_plot <- TRUE }
    
    
    if(tile_plot)
    {
        return(capa_tile_plot(x,variate_names,epoch=epoch,subset=subset))
    }
    else
    {
        return(capa_line_plot(x,variate_names,epoch=epoch,subset=subset))
    }
})







