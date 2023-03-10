# MIT License
#
# Copyright (c) 2023 David L. Donoho, Matan Gavish and Elad Romanov
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

#' Adaptive hard thresholding
#' @description Performs optimal adaptive hard thresholding on the input matrix Y.
#' @param Y A data matrix, on whose singular values thresholding should be performed.
#' @param k An upper bound (potentially loose) on the latent signal rank. That
#'    is, the procedure assumes that there are AT MOST k informative principal
#'    components of Y.
#' @param strategy Method for reconstructing the noise bulk (optional). Can be one of the following:
#'    '0': tranpsort to zero;
#'    'w': winsorization;
#'    'i': imputation (default option).
#' @return
#'    \item{Xest}{An estimate of the low-rank signal. That is: the matrix obtained
#'          by thresholding the singular values of Y.}
#'    \item{Topt}{The hard threshold computed by the procedure. To wit, the procedure
#'      retains the i-th PC of Y if and only if the corresponding singular value, y_i,
#'        satisfies y_i > Topt.}
#'    \item{r}{The number of "relevant" components: r = rank(Xest).}
#' @references David L. Donoho, Matan Gavish and Elad Romanov.
#'        "ScreeNOT: Exact MSE-optimal singular value thresholding in correlated noise."
#'        Annals of Statistics (2023).
#'        \url{https://github.com/eladromanov/ScreeNOT}
#' @author Elad Romanov
#' @examples
#'    Y <- matrix(rnorm(1e6)/sqrt(1e3),nrow=1e3)
#'         # Y is a 1000x1000 i.i.d. Gaussian matrix
#'    val <- ScreeNOT::adaptiveHardThresholding(Y, 10)
#'         # Runs the ScreeNOT procedure, with an upper bound k=10
#'    cat('Computed threshold: ', val$Topt)
#'         # The adaptively computed threshold
#'    cat('Known optimal threshold: ', 4/sqrt(3))
#'         # The known optimal threshold for this noise bulk
#' @export
adaptiveHardThresholding = function(Y, k, strategy='i') {
  Y_svd <- svd(Y)
  fY <- Y_svd$d
  Y_dims <- dim(Y)
  gamma <- min(Y_dims[[1]]/Y_dims[[2]], Y_dims[[2]]/Y_dims[[1]])

  fZ <- createPseudoNoise(fY, k, strategy=strategy)
  Topt <- computeOptThreshold(fZ, gamma)

  fY_new <- fY*(fY>Topt)
  r <- sum( fY>Topt )

  U <- Y_svd$u
  Vt <- t( Y_svd$v )
  Xest <- U %*% diag(fY_new) %*% Vt

  return( list( Xest=Xest, Topt=Topt, r=r ) )
}

#' Creates a "pseudo-noise" singular from the singular values of the observed matrix
#' Y, which is given in the array fY.
#' @param fY a numpy array containing the observed singular values, one which we operate
#' @param k k: an upper bound on the signal rank. The leading k values in fY are discarded
#' @param strategy strategy: one of '0' (tranpsort to zero), 'w' (winsorization), 'i' (imputation)
#'      default='i'    r: the number of relevant components, r = rank(Xest)
#' @noRd
createPseudoNoise = function(fY, k, strategy='i') {
  # sort fZ into increasing order
  fZ <- sort(fY)

  p = length(fZ)
  if (k >= p) {
    stop('k too large. procedure requires k < min(n,p)')
  }

  if (k > 0) {

    # transport to zero
    if (strategy == '0') {
      fZ[(p-k+1):p] <- 0
    }

    # winsorization
    else if (strategy == 'w') {
      fZ[(p-k+1):p] <- fZ[p-k]
    }

    # imputation
    else if (strategy == 'i') {
      if (2*k+1 >= p) {
        stop('k too large. imputation requires 2*k+1 < min(n,p)')
      }
      diff <- fZ[p-k] - fZ[p-2*k]
      for (l in 1:k) {
        a <- (1 - ((l-1)/k)**(2/3)) / (2**(2/3)-1)
        fZ[p-l+1] <- fZ[p-k] + a*diff
      }
    }
    else {
      err_str <- cat('unknown strategy, should be one of \'0\',\'w\',\'i\'. given: ', format(strategy))
      stop( err_str )
    }
  }
  return (fZ)
}

#' Computes the optimal hard thershold for a given (empirical) noise distribution fZ
#' and shape parameter gamma. The optimal threshold t* is the unique number satisfying
#' F_gamma(t*;fZ)=-4 .
#' @param fZ array, whose entries define the counting measure to use
#' @param gamma dim parameter, assumed 0 < gamma <= 1.
#' @noRd
computeOptThreshold = function(fZ, gamma) {
  low <- max(fZ)
  high <- low + 2.0

  while (F(high, fZ, gamma) < -4) {
    low <- high
    high <- 2*high
  }

  # F is increasing, do binary search:
  eps <- 10e-6
  while (high-low > eps) {
    mid <- (high+low)/2
    if (F(mid, fZ, gamma) < -4) {
      low <- mid
    }
    else {
      high <- mid
    }
  }
  return (mid)
}

#' Compute the functional Phi(y;fZ), evaluated at y and counting (discrete) measure
#' defined by the entries of fZ.
#' @param  y values to evaluate at
#' @param fZ array, whose entries define the counting measure to use
#' @noRd
Phi = function(y, fZ) {
  phi <- mean(y/(y**2 - fZ**2))
  return (phi)
}

#' Compute the functional Phi'(y;fZ) (derivative of Phi w.r.t y), evaluated at
#' y and counting (discrete) measure defined by the entries of fZ.
#' @param  y: values to evaluate at
#' @param fZ: array, whose entries define the counting measure to use
#' @noRd
Phid = function(y, fZ) {
  fz2 <- fZ**2
  phid <- (-(y**2+fz2)/(y**2-fz2)**2)
  return( mean(phid) )
}

#' Compute the functional D_gamma(y;fZ), evaluated at y and counting (discrete)
#' measure defined by the entries of fZ, with shape parameter gamma.
#' @param y values to evaluate at
#' @param fZ numpy array, whose entries define the counting measure to use
#' @param gamma shape parameter, assumed 0 < gamma <= 1.
#' @noRd
D = function(y, fZ, gamma) {
  phi <- Phi(y, fZ)
  return (phi * (gamma*phi + (1-gamma)/y))
}

#' Compute the functional D_gamma'(y;fZ) (derivative of D_gamma w.r.t y),
#' evaluated at y and counting (discrete) measure defined by the entries of fZ,
#' with shape parameter gamma.
#' @param y values to evaluate at
#' @param fZ numpy array, whose entries define the counting measure to use
#' @param gamma shape parameter, assumed 0 < gamma <= 1.
#' @noRd
Dd = function(y, fZ, gamma) {
  phi <- Phi(y, fZ)
  phid <- Phid(y, fZ)
  return (phid * (gamma*phi + (1-gamma)/y) + phi * (gamma*phid - (1-gamma)/y**2))
}

#' Compute the functional Psi_gamma(y;fZ), evaluated at y and counting (discrete)
#' measure defined by the entries of fZ, with shape parameter gamma.
#' @param y values to evaluate at
#' @param fZ numpy array, whose entries define the counting measure to use
#' @param strategy gamma: shape parameter, assumed 0 < gamma <= 1.
#' @noRd
F = function(y, fZ, gamma) {
  d <- D(y, fZ, gamma)
  dd <- Dd(y, fZ, gamma)
  return (y * dd / d)
}
