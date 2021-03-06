#' Sales Taxes
#' Welfare Extrapolation
#' Consumer Surplus Change
#' This is a Non-Linear optimization. We use many inputs and functions
#' First, as functions we define all the definitions that are general enough to test different scenarios
#' Then we get several inputs: constraint matrices, minimum criterion's used before and estimated bounds
#' Finally, we create more functions (for the constraints, as they vary depending the scenario)
#' We put everything together and run the nonlinear optimization problem for each state in a given scenario, varying cases
#' We estimate using a derivative-free algorithm


library(Matrix)
library(data.table)
library(ggplot2)
library(zoo)
library(tidyverse)
library(stringr)
library(nloptr)
library(doParallel)
library(MASS)
library(pracma)

setwd("/project2/igaarder")


#### Objective Function and derivatives ----------------

## These functions are general enough to produce different scenarios
# They need, in the end:

# mu: the vector of parameters (control variables)
# data: the name of the data set 
# act.p: the name of the variable of log prices (consumer)
# tax: the name of the log tax variable
# change: the value of the new sales tax to extrapolate
# w: variable of weights
# K: order of the polynomial used
# min: minimum value of the support of shape constraint
# max: maximum value of the support of shape constraint



# Normalization function for bernstein polynomial
normalize <- function(p, min, max) {
  (p - min)/(max - min)
}

# Bernstein polynomial
bernstein <- function(p, k, K, min, max){
  p <- normalize(p, min, max)
  choose(K, k) * p^k * (1 - p)^(K - k)
}
# Integral of the bernstein (demand is actually this: to use the previous results and don't change everything)
int.bernstein <- function(p, k, K, min, max) {
  
  j <- (k+1):(K+1)
  b_k <- sapply(j, function (j, p, k, K, min, max) bernstein(p,k = j, K, min, max), p = p, K = K + 1, min = min, max = max)
  
  return(sum(b_k)/(K+1))
}

# Integrand: here is where parameters appear for the first time
# Objective
integrand <- function(p, mu, K, min, max) {
  polynomial <- rep(0,K)
  for (k in 1:K) {
    polynomial[k] <- int.bernstein(p, k, K-1, min, max)
  }
  return(exp(sum(mu*polynomial) + p))
}
# derivative for mu_k
integrand.d <- function(p, mu, K, min, max, k) {
  polynomial <- rep(0,K)
  for (i in 1:K) {
    polynomial[i] <- int.bernstein(p, i, K-1, min, max)
  }
  return(int.bernstein(p, k, K-1, min, max)*exp(sum(mu*polynomial) + p))
}

# Apply integral to every value of p (this so the integral function can use vectors)
# Objective
int.apply <- function(x, mu, K, min, max) {
  sapply(x, integrand, mu=mu, K=K, min=min, max=max)
}
# Derivative
d.int.apply <- function(x, mu, K, min, max, k) {
  sapply(x, integrand.d, mu=mu, K=K, min=min, max=max, k = k)
}
exp.sales <- function(p, mu, K, min, max) {
  polynomial <- rep(0,K)
  for (k in 1:K) {
    polynomial[k] <- int.bernstein(p, k, K-1, min, max)
  }
  return(exp(sum(mu*polynomial)))
}
common_term <- function(p, mu, K, min, max) {
  
  return(sapply(p, function(x, mu, K, min, max) 
    exp.sales(p = x, mu = mu, K = K, min = min, max = max), 
    mu = mu, K = K, min = min, max = max))
}

# Objective function: include arguments for constraints even if not needed
expected.CS.change <- function(mu, data, act.p, tax, t, w, min, max, K, constr_mat, IV_mat, min.crit = 0, elas = T) {
  
  # mu: the vector of parameters (control variables)
  # data: the name of the data set 
  # act.p: the name of the variable of log prices (consumer)
  # tax: the name of the log tax variable
  # change: the value of the new sales tax to extrapolate
  # w: variable of weights
  # K: order of the polynomial used
  # min: minimum value of the support of shape constraint
  # max: maximum value of the support of shape constraint
  
  # Use vectors 
  ll <- data[[act.p]] 
  ul <- data[[act.p]] - data[[tax]] + t
  
  # Put together and transform to list
  X <- rbind(ll, ul)
  X <- lapply(seq_len(ncol(X)), function(i) X[,i])
  
  # sapply from list
  int <- sapply(X, function(x, mu, K, min, max) 
    integrate(int.apply, 
              lower = x["ll"], 
              upper = x["ul"], 
              mu = mu,
              K = K, 
              min = min, 
              max = max)$value, mu = mu, K = K,  min = min, max = max)
  
  # get the weights
  w <- data[[w]]
  # Divide by initial current sales
  p_m <- data[[act.p]] - data[[tax]]
  or <- common_term(p = ll, mu = mu, K = K, min = min, max = max)*exp(p_m)
  int <- int/or
  
  # Return weighted average
  return(weighted.mean(int, w = w))

}
# Objective function max.

max_expected.CS.change <- function(mu, data, act.p, tax, t, w, min, max, K, constr_mat, IV_mat, min.crit = 0, elas = T) {
  return(-expected.CS.change(mu, data, act.p, tax, t, w, min, max, K, constr_mat, IV_mat, min.crit, elas))
}

# derivative w. respect to mu_k
d.mu.k.expected.CS.change <- function(mu, data, act.p, tax, t, w, min, max, K, k) {
  
  # k: mu_k degree for derivative
  # the rest as above
  
  # Use vectors 
  ll <- data[[act.p]] 
  ul <- data[[act.p]] - data[[tax]] + t
  
  # Put together and transform to list
  X <- rbind(ll, ul)
  X <- lapply(seq_len(ncol(X)), function(i) X[,i])
  
  # sapply from list
  int <- sapply(X, function(x, mu, k, K, min, max) 
    integrate(d.int.apply, 
              lower = x["ll"], 
              upper = x["ul"], 
              mu = mu,
              K = K, 
              min = min, 
              max = max,
              k = k)$value, mu = mu, K = K, k = k, min = min, max = max)
  
  # get the weights
  w <- data[[w]]
  # Divide by initial current sales derivative
  p_m <- data[[act.p]] - data[[tax]]
  or <- common_term(p = ll, mu = mu, K = K, min = min, max = max)*exp(p_m)
  
  p.0 <- sapply(ll, function(x,k,K,min,max)
    int.bernstein(p = x, k = k, K = K, min = min, max = max),
    k = k, K = K, min = min, max = max)
  
  int <- -p.0*int/or
  
  # Return weighted average
  return(weighted.mean(int, w = w))
  
}

# Finally, a function that evaluates every gradient: include here arguments for constraint so it runs
eval_grad <- function(mu, data, act.p, tax, t, w, min, max, K, constr_mat, IV_mat, min.crit = 0, elas = T) {
  k <-1:K
  der <- sapply(k, function(x, data, act.p, tax, t, w, k, K, min, max) 
    d.mu.k.expected.CS.change(mu = mu, data = data, act.p = act.p, 
                              tax = tax, t = t, w = w, min = min, 
                              max = max, K = K, k = x),
    data = data, act.p = act.p, tax = tax, t = t, w = w, K = K, min = min, max = max)
  return(t(t(der)))
}
max_eval_grad <- function(mu, data, act.p, tax, t, w, min, max, K, constr_mat, IV_mat, min.crit = 0, elas = T) {
  return(-eval_grad(mu, data, act.p, tax, t, w, min, max, K, constr_mat, IV_mat, min.crit, elas))
}

#### Constraints functions ----------

## Now, we put together functions that create the restrictions for the problem and will be used in the NLOPT program

# The final function takes 5 main inputs:
# mu: the control variables
# constr_mat = the matrix of constraint
# IV_mat = the vector of IVs, used for the RHS of the restriction
# elas = T (default) indicates we are imposing shape constraint on the elasticity (F is for demand)
# min.crit = (default 0) indicates the value of the minimum criterion for the problem (as solved earlier). If NULL the problem is on an equality

## Function without min.criterion
constraint <- function(mu, constr_mat, IV_mat) {
  
  if (dim(constr_mat)[1] != length(IV_mat)) { stop("constr_mat and IV_mat dimensions must match") }
  if (length(mu) != dim(constr_mat)[2]) { stop("constr_mat and mu dimensions must match") }
  
  constraints <- NULL
  for (r in 1:dim(constr_mat)[1]) {
    constraints <- rbind(constraints, c(sum(constr_mat[r,]*mu) - IV_mat[r]))
  }
  return(constraints)
}
## Function to add min.cretrion = value
constr.min.crit <- function(mu, constr_mat, IV_mat, min.crit) {
  
  if(length(min.crit) > 1){ stop("minimum criterion should be a value") }
  
  return(
    rbind(
      constraint(mu, constr_mat, IV_mat+min.crit),
      constraint(mu, -constr_mat, -IV_mat+min.crit)
    )
  )
}
## Function to create the shape constraint
shape.constr<-function(mu, elas) {
  constr.mono <- NULL
  if (elas) {
    for (k in 1:K) {
      
      constr.mono <- rbind(constr.mono,
                           c(mu[k]))
    }
  } else {
    for (k in 1:(K-1)) {
      
      constr.mono <- rbind(constr.mono,
                           c( -mu[k] + mu[k+1]))
    }
  }
  return(constr.mono)
}
## Function for constraint: includes the arguments from evaluation function even if not needed so it runs
eval_restrictions <- function(mu, data, act.p, t, tax, w, min, max, K, constr_mat, IV_mat, min.crit = 0, elas = T) {
  
  return(
    as.matrix(
      #rbind(
      constr.min.crit(mu, constr_mat, IV_mat, min.crit) #,
      #shape.constr(mu, elas)
      #)
    )
  )
}
## Function for jacobian
eval_restrictions_j <- function(mu, data, act.p, t, tax, w, min, max, K, constr_mat, IV_mat, min.crit = 0, elas = T) {
  
  constr.jac <- NULL
  for (k in 1:K) {
    
    constr.jac <- cbind(
      constr.jac,
      #rbind(
      constr.min.crit(c(rep(0,k-1),1,rep(0,K-k)), constr_mat, rep(0, dim(constr_mat)[1]), 0) #,
      #shape.constr(c(rep(0,k-1),1,rep(0,K-k)), elas)
      #)
    )
    
  }
  
  return(as.matrix(constr.jac))
  
}

#### Prepare and run optimizations -----


## Small function to get an initial value for optimization
get.init.val <- function(A, b, min.c, max = 1000) {
  
  init <- as.vector(ginv(A) %*% b)
  if (sum(init> 0) == 0) {
    return(init)
  } 
  else {
    srv <- (sum(init> 0) > 0)
    d <- dim(A)[2]
    kernel <- null(A)
    if (is.null(kernel)) kernel <- t(t(rep(0, length(init)))) # When it has a solution then is going to be null: use only min.criterion
    for (d in 1:dim(kernel)[2]) {
      ker <- as.vector(kernel[,d])
      i <- 0
      print(paste0("Attempt ", i, ":"))
      print(init)
      print(ker)
      while (srv & i < max) {
        i <- i + 1
        s <- sign(ker[which(init == max(init))])
        rat <- abs( ker[which(init == max(init))]/min(init))
        if (min.c == 0) {
          init <- init - s*rat*ker
        }
        else {
          init <- init - s*rat*ker -
            (init > 0)*rep(sum(init < 0)*min.c/(d), length(init)) + 
            (init < 0)*rep(sum(init < 0)*min.c/(d), length(init))          
        }
        if (i < 11 & round(5*i/max) == 5*i/max) {
          print(paste0("Attempt ", i, ":"))
          print(init)
        } 
        srv <- (sum(init> 0) > 0)
      }
    }
    if (i == max) {
      # Set 1 of them to 0
      m <- dim(A)[2] -1
      if (m > 1){
        A <- A[,1:m]
        init <- c(get.init.val(A, b, min.c, max), 0)
        
      }
      else {
        stop("Algorithm Failed") 
      }
    }
    else {
      return(init)
    }
  }
}


# 0. Parallelize options
# use the environment variable SLURM_NTASKS_PER_NODE to set the number of cores
registerDoParallel(cores=(Sys.getenv("SLURM_NTASKS_PER_NODE")))

# 1. Open data
data <- fread("Data/extraction_state_binned_price.csv")

# 2. Open IVs: constant across K & D
res.ivs <- fread("Data/Demand_iv_sat_initial_price_semester_boot_r.csv")
## Keep iterest results
res.ivs <- res.ivs[controls == "group_division_by_module_by_time" & iter == 0][, -c("iter", "controls")]
# dcast outcomes
res.ivs <- dcast(res.ivs, n.groups + lev ~ outcome,  fun=sum, value.var = c("Estimate"))
# Calculate IV
res.ivs[, estimate := w.ln_quantity3/w.ln_cpricei2]
# Order appropiately
res.ivs <- res.ivs[order(n.groups, lev)]

## 2. Load min and max p for support
res.pq <- fread("Data/Demand_pq_sat_initial_price_semester_extrapolate.csv")

## 3. Load min criteria
min.criteria <- fread("Data/table_mincreteria_extrapolation.csv")
setnames(min.criteria, c("K", "D", "sc"), c("Degree", "L", "extrap"))

## 4. Load previous solutions of the linear problem, to start there
mus <- fread("Data/elasticity_mu_bounds_table_state_extrapolation.csv")
mus <- mus[target == "elas" & taxability == "taxable" & !is.na(mu.up)][, -c("up", "down", "target", "taxability")]
setnames(mus, c("K", "D", "sc"), c("Degree", "L", "extrap"))

# 5. Define output and Ks to test
out.file <- "Data/consumer_surplus_changes_ex1b.csv"
# K.test <- c(7,10)
K.test <- c(2,3,7,10)

# 6. Set up Optimization Parameters (algorithm for now)
nlo.opts.local.df <- list(
  "algorithm"="NLOPT_LN_COBYLA",
  "maxeval" = 400,
  "xtol_rel"=1.0e-8
)
# nlo.opts.local <- list(
#   "algorithm"="NLOPT_LD_SLSQP",
#   "maxeval" = 100,
#   "xtol_rel"=1.0e-8,
#   "check_derivatives_print" = "all"
#   
# )



## 6. Loop acorss Scenarios
scenarios <- c("No Tax", "plus 5 Tax")
welfare <- data.table(NULL)

for (sc in scenarios) {
  
  p.min <- res.pq[extrap == sc][["min.p"]]
  p.max <- res.pq[extrap == sc][["max.p"]]
  
  if (sc == "No Tax") {
    tax.cs <- "tau"
    t.cs <- 0
  } 
  if (sc == "plus 5 Tax")  {
    data[, tau.n := 0]
    tax.cs <- "tau.n"
    t.cs <- log(1+0.05)
    
  }
  ## Loop across K
  for (K in K.test) {
    
    ## 6.1. Load Matrix of gamma (this extrictly depends on K since the basis change)
    in.file <- paste0("Data/Demand_gamma_sat_initial_price_semester_extrapolate_K", K,"_bern.csv")
    gamma.full.data <- fread(in.file)
    
    ## 6.2 Restrict gamma file. Constant across p
    gamma <- gamma.full.data[extrap == sc & n.groups < 3][, c(paste0("b", 0:(K-1)), "n.groups"), with = F]             ## For elasticity
    
    ## 6.3 Start Loop at number of groups
    for (D in unique(gamma$n.groups)) {
      
      ## A1. Build the constraints matrix 
      constr <- as.matrix(gamma[n.groups == D][, -c("n.groups")])   ## For elasticity
      
      ## A2. Load min.criterion for case (note that if there is no value it is 0)
      mc <- min.criteria[Degree == K & L == D & extrap == sc,][["min.criteria"]]
      if (is_empty(mc)) mc <- 0
      
      ## A3. Retrieve IVs
      IVs <- res.ivs[n.groups == D][["estimate"]] 
      
      
      print(K)
      print(D)
      print(constr)
      print(IVs)
      print(mc)
      ## Generate an initial value somewhere in the middle to test algorithms
      init.val0 <- get.init.val(constr, IVs, mc)
      print(init.val0)
      
      ## A4. Loop across states
      welfare.st <- foreach (state= unique(mus$st), .combine=rbind) %dopar% {
        
        ## Generate an initial value somewhere in the middle
        # init.val.up <- mus[Degree == K & L == D & st == 19 & state == sc,][["mu.up"]]
        # init.val.down <- mus[Degree == K & L == D & st == 19 & state == sc,][["mu.down"]]

        # B2. Subset data
        st.data <- data[fips_state == state,]
        
        # B2.B1 Run minimization: derivative free 
        res0 <- nloptr( x0=init.val0,
                        eval_f= expected.CS.change,
                        eval_g_ineq = eval_restrictions,
                        opts = nlo.opts.local.df,
                        data = st.data,
                        act.p = "p_m", 
                        t = t.cs, 
                        tax = tax.cs,
                        w = "eta_m", 
                        min = p.min, 
                        max = p.max, 
                        K = K,
                        constr_mat = constr, 
                        IV_mat = IVs, 
                        min.crit = mc,
                        elas = T,
                        ub = rep(0, K),
                        lb = rep(min(IVs)/min(constr), K)
        )       
        # init.val.down <- res0$solution
        # 
        #       # B3. Run minimization. Local
        # res0 <- nloptr( x0=init.val.down,
        #                 eval_f= expected.CS.change,
        #                 eval_grad_f=eval_grad,
        #                 eval_g_ineq = eval_restrictions,
        #                 eval_jac_g_ineq = eval_restrictions_j,
        #                 opts = nlo.opts.local,
        #                 data = st.data,
        #                 act.p = "p_m", 
        #                 tax = tax.cs, 
        #                 t = t.cs, 
        #                 w = "eta_m", 
        #                 min = p.min, 
        #                 max = p.max, 
        #                 K = K,
        #                 constr_mat = constr, 
        #                 IV_mat = IVs, 
        #                 min.crit = mc,
        #                 elas = T,
        #                 ub = rep(0, K),
        #                 lb = rep(-100, K)
        # )
        # B3. Extract minimization results
        down <- res0$objective
        s1 <- res0$status
        
        # B3.B1 Run maximization: derivative free 
        res0 <- nloptr( x0=init.val0,
                        eval_f= max_expected.CS.change,
                        eval_g_ineq = eval_restrictions,
                        opts = nlo.opts.local.df,
                        data = st.data,
                        act.p = "p_m", 
                        t = t.cs, 
                        tax = tax.cs,
                        w = "eta_m", 
                        min = p.min, 
                        max = p.max, 
                        K = K,
                        constr_mat = constr, 
                        IV_mat = IVs, 
                        min.crit = mc,
                        elas = T,
                        ub = rep(0, K),
                        lb = rep(min(IVs)/min(constr), K)
        )       
        # init.val.down <- res0$solution
        # # B4. Run maximization. Local
        # res0 <- nloptr( x0=init.val.up,
        #                 eval_f= max_expected.CS.change,
        #                 eval_grad_f = max_eval_grad,
        #                 eval_g_ineq = eval_restrictions,
        #                 eval_jac_g_ineq = eval_restrictions_j,
        #                 opts = nlo.opts.local,
        #                 data = st.data,
        #                 act.p = "p_m", 
        #                 tax = tax.cs, 
        #                 t = t.cs, 
        #                 w = "eta_m", 
        #                 min = p.min, 
        #                 max = p.max, 
        #                 K = K,
        #                 constr_mat = constr, 
        #                 IV_mat = IVs, 
        #                 min.crit = mc,
        #                 elas = T,
        #                 ub = rep(0, K),
        #                 lb = rep(-100, K)
        # )
        # B5. Extract minimization results
        up<- -res0$objective
        s2 <- res0$status
        
        # B6. Compile estimates export
        data.table(data.table(down, up, state, D , K, sc, s1, s2))

      }
      welfare <- rbind(welfare, welfare.st)
      
      # B7. Export Results every case is done
      fwrite(welfare, out.file)
      
    }
    
  }
  
}


