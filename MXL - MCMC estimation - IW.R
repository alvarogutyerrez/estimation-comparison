#####-----#####-----#####-----#####
## D.Akinc - June 2017
## R code for the Hierarchical Bayes Estimation of the Mixed Logit Model
## by using the Inverse Wisharts prior for the covariance matrix
## 
## The file "xmat.csv" follows the long-format style
## e.g.
## [Att11 | Att12 | Att21 | Att22 | Att31 | Att32 ]
## The file "ymat.csv" contains the choices of each respondent for each choice set.
##

library(MASS)
# install.packages("MCMCpack")
require(MCMCpack)

rm(list=ls())
Sys.time()->start;

# Dataset setup
nalts = 3 #num of alternatives
nsets = 18 #num of choice sets
nres = 200 #num of respodents
df = 6 #num of model parameters

# MCMC Settings
nsample = 30000
nburnin = 70000
nskip = 1

# Hyperparameters for Inverse Wishart
# The hyperparameters of IW priors used in the Simulation Study, respectively:
# (1) IW1 --> nu = df & V = diag(df)
# (2) IW2 --> nu = df & V = nu * diag(df)
# (3) IW3 --> nu = (df+1) & V = nu * diag(df)
# (4) IW4 --> nu = (df+3) & V = nu * diag(df)
# (5) IW5 --> nu = (df+4) & V = nu * diag(df)
# (6) IW6 --> nu = 0.5 * (df * (df+1)) & V = 0.1 * nu *diag(df)
nu = df+4  #nu = p
V = nu * diag(df) #T = v*I  

# Importing data
xmat <- read.table("/xmat.csv",header=TRUE,sep=";")
ymat <- read.table("/ymat.csv",header=TRUE,sep=";")
x=t(t(xmat))
y=t(t(ymat))
y=t(y)
# i=1 
# xind=((i-1)*nsets*nalts*nres+1):(i*nsets*nalts*nres) 
# yind=((i-1)*nres+1):(i*nres)
# x=xmat[xind,]
# y=ymat[yind,]; y=t(y)

# True Population parameters used in simulating choice data  
truebeta <- read.table("/betatrue.csv",header=T, sep=";")
truebeta = t(truebeta)
truemu  = 2.0*c(-1.0,0.0,-1.0,0.0,-1.0,0.0)
sigmatrue = 1.0*diag(df)
nlong = (df*(df+1))/2;
sigmatruelong = matrix(0,nlong,1)
j2 = 0;
for (s in 1:df){
  j1 = j2 + 1
  j2 = j1 + (df - s)
  sigmatruelong[j1:j2,] = sigmatrue[s:df,s]}

#####-----#####-----#####-----#####
## Estimation 
#####-----#####-----#####-----#####
## Function for computing the loglikelihood of MNL model
loglike = function(nalts,nsets,nres,betan,y,X){
  #Function for computing the loglikelihood of MNL model
  logl = matrix(0,1,nres)
  for (r in 1:nres){
    tt = ((r-1)*nalts*nsets+1):(r*nalts*nsets)
    Xsub = X[tt,]
    row = nrow(Xsub)
    nset = row/nalts
    logl[,r] = 0
    for (s in 1:nset){
      xx = Xsub[((s-1)*nalts+1):(s*nalts),]
      m = max(xx[1,]%*%betan[,r], xx[2,]%*%betan[,r])
      #m = max(xx[1,]%*%betan[,r], xx[2,]%*%betan[,r], xx[3,]%*%betan[,r])
      u = (xx%*%betan[,r])-m
      p = exp(u) / sum(exp(u))
      logl[,r] = logl[,r] + log(p[y[s,r],])
    }
  }
  return(logl)
}

## Function for the conditional posterior of MU_BETA
nextmu = function(nres,betan,Sigma){
  lb = t(chol(Sigma))
  ndf = ncol(Sigma)
  zr = matrix(rnorm(ndf),nrow=ndf,ncol=1)
  munew = rowMeans(betan)+((lb%*%zr)/sqrt(nres))
  return(munew)
}

## Function for the conditional posterior of BETA_N
nextbeta = function(nres,betan,rho,mu,Sigma,y,X,logLold){
  lb = t(chol(Sigma))
  ndf = ncol(Sigma)
  zr = matrix(rnorm(df*nres),nrow=df, ncol=nres)
  betanew = betan + sqrt(rho)*(lb%*%zr)
  bn = betanew - matrix(mu,nrow=ndf,ncol=nres)
  bo = betan - matrix(mu,nrow=ndf,ncol=nres)
  logLnew = loglike(nalts,nsets,nres,betanew,y,X)
  varmat1 = bn * (solve(Sigma)%*%bn)
  varmat2 = bo * (solve(Sigma)%*%bo)
  r = exp(logLnew - logLold - 0.5 * (colSums(varmat1) - colSums(varmat2)))
  ind = (matrix(runif(nres),nrow=1,ncol=nres)<=r)
  meanind = rowSums(ind)/nres
  newrho = rho - 0.001*(meanind<0.3)+0.001*(meanind>0.3)
  logLnew = logLnew*ind+logLold*(1-ind)
  bnew = (betanew*1*matrix(rep(ind,ndf),nrow=ndf,ncol=nres,byrow=T))+(betan*1*matrix(rep((1-ind),ndf),nrow=ndf,ncol=nres,byrow=T))
  betaoutlist = list(bnew=bnew,logLnew=logLnew,newrho=newrho,meanind=meanind)
  return(betaoutlist)
}

#------------------------------------------------------------------------#
#Based on the chosen prior for covariance matrix, the function for the 
#conditional posterior  of SIGMA_BETA (named "nextSigma") and the Gibbs
#Sampling function for updating the all parameters (named "rgibbs") change.
#------------------------------------------------------------------------#
#------------------------------------------------------------------------#
###(I.) Under the inverse Wishart prior
## Function for the conditional posterior of SIGMA_BETA
nextSigma = function(nres,df,nu,V,betan,mu){
# Option 1
  # S = (betan - matrix(mu,nrow=df,ncol=nres))
  # Sigmanew = S%*%t(S) + V
  # lb = t(chol(solve(Sigmanew)))
  # zr = matrix(rnorm(df*(df+nu+nres)),nrow=df, ncol=(df+nu+nres))
  # ss = lb%*%zr
  # Sigmanew = solve(ss%*%t(ss))
  
# Option 2 - with MCMCpack  
  S = (betan - matrix(mu,nrow=df,ncol=nres))
  Vnew = S%*%t(S) + V
  Sigmanew = riwish(nu+nres,Vnew)
  return(Sigmanew)
  }

## Function for updating all parameters by using the Gibbs Sampling
rgibbs = function (nalts,nsets,df,nres,nsample,nburnin,nu,V,y,X){
  #starting values:
  mu = matrix(((runif(1)*4)-2),df,1)
  betao = matrix(mu,nrow=df,ncol=nres)
  Sigma = (runif(1)*6)*diag(df)
  rho = 0.01
  #Storage for all draws 
  mudraw = matrix(0,df,nsample)
  Sigmadraw = matrix(0,(df*nsample),df)
  betamean = matrix(0,df,nres)
  
  logLold = loglike(nalts,nsets,nres,betao,y,X)
  
  ndraw = nburnin + nsample*nskip
  for (r in 1:ndraw){
    newbetout = nextbeta(nres,betao,rho,mu,Sigma,y,X,logLold)
    betao = newbetout$bnew
    logLold = newbetout$logLnew
    rho = newbetout$newrho
    mu = nextmu(nres,betao,Sigma)
    Sigma = nextSigma(nres,df,nu,V,betao,mu)
    nk = (r-nburnin)/nskip
    if(r>nskip & floor(nk)==nk & nk>0){
      mudraw[,nk]=mu
      nnk = ((nk-1)*df+1):(nk*df)
      Sigmadraw[nnk,]=Sigma
      betamean = betamean+betao
    }
  }
  betamean = betamean / nsample
  mumean = rowMeans(mudraw)
  sigmamean = matrix(0,df,df)
  for(i in 1:nsample){
    k=((i-1)*df+1):(i*df)
    sigmamean = sigmamean + Sigmadraw[k,]
  }
  sigmamean = sigmamean / nsample
  return (list(betamean=betamean,mumean=mumean,sigmamean=sigmamean))
}

estout=rgibbs(nalts,nsets,df,nres,nsample,nburnin,nu,V,y,x)

#####-----#####-----#####-----#####
## Results from Estimation
#####-----#####-----#####-----#####
estbeta = estout$betamean
estmu = estout$mumean
estsigma = estout$sigmamean

#####-----#####-----#####-----#####
## Computation of RMSEs
#####-----#####-----#####-----#####
# RMSE_BETA:
betasum = 0
for (m in 1:nres){
	betasum = betasum + (t(estbeta[,m]-truebeta[,m])
			%*%(estbeta[,m]-truebeta[,m]))}
RMSEbeta = sqrt(betasum/(nres*df))

# RMSE_MU
RMSEmu = sqrt((t(estmu - truemu)%*%(estmu - truemu))/df)

# RMSE_SIGMA
sigmameanlong = matrix(0,nlong,1)
j2 = 0;
for (t in 1:df){
	j1 = j2 + 1
    j2 = j1 + (df - t)
    sigmameanlong[j1:j2,] = estsigma[t:df,t]}
RMSEsigma = sqrt((t(sigmameanlong - sigmatruelong)%*%(sigmameanlong - sigmatruelong))/nlong)
RMSEmatrix = cbind(RMSEbeta,RMSEmu,RMSEsigma)

print(Sys.time()-start);

# Exportin the Estimates and the RMSE values
# write.table(estbeta, file = "/estbeta.csv", row.names = FALSE,sep=";")
# write.table(estmu, file = "/estmu.csv", row.names = FALSE,sep=";")
# write.table(estsigma, file = "/estsigma.csv", row.names = FALSE,sep=";")
# write.table(RMSEmatrix, file = "/RMSE.csv", row.names = FALSE,sep=";")
cat("Estimation Procedure is finalized")