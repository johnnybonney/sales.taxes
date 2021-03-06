#' Sales Taxes Project
#' Robustness Check Heterogeneity: After checking our estimates don't really change when looking at the 
#' sample w. observed demographics, we start running the robustness checks by groups defined by different demographics.
#' We run the second spec (fully sat) but we now play furthermore with the number of categories: terciles, quartiles, etc
#' Update Demographics and add some others


library(data.table)
library(futile.logger)
library(lfe)
library(multcomp)


setwd("/project2/igaarder")


## input filepaths -----------------------------------------------
#' This data is the same as all_goods_pi_path, except it has 2015-2016 data as well.
data.semester <- "Data/Nielsen/semester_nielsen_data.csv"
data.stores <- "Data/Nielsen/stores_all.csv"


## output filepaths ----------------------------------------------
results.file <- "Data/robust_demog_het_fullsat_estimates_initprice_semester.csv"
theta.results.file <- "Data/Demand_theta_robust_demog_het_fullsat_initprice_semester.csv"

### Set up Semester Data ---------------------------------
all_pi <- fread(data.semester)
all_pi[, w.ln_sales_tax := ln_sales_tax - mean(ln_sales_tax), by = .(store_by_module)]
all_pi[, w.ln_cpricei2 := ln_cpricei2 - mean(ln_cpricei2), by = .(store_by_module)]
all_pi[, w.ln_quantity3 := ln_quantity3 - mean(ln_quantity3), by = .(store_by_module)]

# Need to demean
all_pi[, module_by_time := .GRP, by = .(product_module_code, semester, year)]
all_pi[, L.ln_cpricei2 := ln_cpricei2 - D.ln_cpricei2]
all_pi[, dm.L.ln_cpricei2 := L.ln_cpricei2 - mean(L.ln_cpricei2, na.rm = T), by = module_by_time]
all_pi[, dm.ln_cpricei2 := ln_cpricei2 - mean(ln_cpricei2, na.rm = T), by = module_by_time]
all_pi[, dm.ln_quantity3 := ln_quantity3 - mean(ln_quantity3, na.rm = T), by = module_by_time]


# Defining common support
control <- all_pi[D.ln_sales_tax == 0,]
treated <- all_pi[D.ln_sales_tax != 0,]

# Price 
pct1.control <- quantile(control$dm.L.ln_cpricei2, probs = 0.01, na.rm = T, weight=control$base.sales)
pct1.treated <- quantile(treated$dm.L.ln_cpricei2, probs = 0.01, na.rm = T, weight=treated$base.sales)

pct99.control <- quantile(control$dm.L.ln_cpricei2, probs = 0.99, na.rm = T, weight=control$base.sales)
pct99treated <- quantile(treated$dm.L.ln_cpricei2, probs = 0.99, na.rm = T, weight=treated$base.sales)

all_pi[, cs_price := ifelse(dm.L.ln_cpricei2 > max(pct1.treated, pct1.control) & 
                              dm.L.ln_cpricei2 < min(pct99treated, pct99.control), 1, 0)]
# Make sure missings are 0s
all_pi[, cs_price := ifelse(is.na(dm.L.ln_cpricei2), 0, cs_price)]

## Keep within the common support
all_pi <- all_pi[cs_price == 1,]

## cut the tails (keep between 1st and 99th percentile)
pct1 <- quantile(all_pi$dm.ln_cpricei2, probs = 0.01, na.rm = T, weight=base.sales)
pct99 <- quantile(all_pi$dm.ln_cpricei2, probs = 0.99, na.rm = T, weight=base.sales)
all_pi <- all_pi[(dm.ln_cpricei2 > pct1 & dm.ln_cpricei2 < pct99),]

## Merge Stores characteristics
stores <- fread(data.stores)
all_pi <- merge(all_pi, stores, by = c("year", "store_code_uc"), all.x = T)

## Keep only the stores with observed characteristics 
all_pi <- all_pi[!is.na(av_hh_income_sales)]


## Run estimations -----------------

FE_opts <- c("group_region_by_module_by_time", "group_division_by_module_by_time")
outcomes <- c("w.ln_cpricei2", "w.ln_quantity3")
demographics <- c("av_hh_income_trips", 'per_bachelor_25_trips', 'median_age_trips',
                  'per_hisp_trips', 'per_black_trips', 'per65_trips')


LRdiff_res <- data.table(NULL)
target_res <- data.table(NULL)
## Loop over the demographic we look at
for (dem in demographics) {
  for (sat.groups in 2:5) {
    
    # Divide the sample by the demographic's quantiles (at the level store)
    median <- all_pi[, .(D = mean(get(dem), na.rm = T)), by = .(store_code_uc)]
    median <- median[, het := cut(D, breaks = quantile(D, probs = seq(0, 1, by = 1/sat.groups), na.rm = T),
                                       labels = 1:sat.groups, right = FALSE)]
    all_pi_het <- merge(all_pi, median, by = "store_code_uc")

    # Saturate fixed effects
    all_pi_het[, dem_group_region_by_module_by_time := .GRP, by = .(region_by_module_by_time, het)]
    all_pi_het[, dem_group_division_by_module_by_time := .GRP, by = .(division_by_module_by_time, het)]
    
    ## Loop over number of quantiles of initial prices
    for (n.g in 1:5) {
      
      # Create groups of initial values of tax rate
      # We use the full weighted distribution
      all_pi_het <- all_pi_het[, quantile := cut(dm.L.ln_cpricei2,
                                         breaks = quantile(dm.L.ln_cpricei2, probs = seq(0, 1, by = 1/n.g), na.rm = T, weight = base.sales),
                                         labels = 1:n.g, right = FALSE)]
      quantlab <- round(quantile(all_pi_het$dm.L.ln_cpricei2, 
                                 probs = seq(0, 1, by = 1/n.g), na.rm = T, 
                                 weight = all_pi_het$base.sales), digits = 4)
      # Saturate fixed effects
      all_pi_het[, group_region_by_module_by_time := .GRP, by = .(region_by_module_by_time, quantile)]
      all_pi_het[, group_division_by_module_by_time := .GRP, by = .(division_by_module_by_time, quantile)]
      
      ##### Run fully saturated: split sample
      
      for (d in 1:sat.groups) {
        
        # Keep sample we use for estimation
        sample <- all_pi_het[het == d]
        
        # Capture sample proportion
        prop <- nrow(sample)/nrow(all_pi[!is.na(dem)])
        
        
        ## Estimate RF and FS
        for (FE in FE_opts) {
          for (Y in outcomes) {
            formula1 <- as.formula(paste0(
              Y, " ~ w.ln_sales_tax:quantile | ", FE, "+ quantile"
            ))
            if (n.g == 1) { formula1 <- as.formula(paste0(Y, " ~ w.ln_sales_tax  | ", FE)) }
            res1 <- felm(formula = formula1, data = sample,
                         weights = sample$base.sales)
            
            
            ## attach results
            res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
            res1.dt[, outcome := Y]
            res1.dt[, controls := FE]
            res1.dt[, n.groups := n.g]
            res1.dt[, lev := quantlab[-1]]
            res1.dt[, het := dem]
            res1.dt[, het.g := d]
            res1.dt[, n.het.g := sat.groups]
            
            ## Descriptives
            res1.dt$N_obs <- nrow(sample)
            res1.dt$N_stores <- uniqueN(sample, by = c("store_code_uc") )
            res1.dt$N_modules <- length(unique(sample$product_module_code))
            res1.dt$N_counties <- uniqueN(sample, by = c("fips_state", "fips_county"))
            res1.dt$N_years <- uniqueN(sample, by = c("year")) # should be 6 (we lose one because we difference)
            res1.dt$N_county_modules <- uniqueN(sample, by = c("fips_state", "fips_county",
                                                               "product_module_code"))
            LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
            fwrite(LRdiff_res, results.file)
          }
          
          ## Estimate IVs and retrieve in vector
          IV <- LRdiff_res[outcome == "w.ln_quantity3" & n.groups == n.g & controls == FE &
                             n.het.g == sat.groups & het == dem & het.g == d,][["Estimate"]]/LRdiff_res[outcome == "w.ln_cpricei2" &
                                                                                                    n.groups == n.g & controls == FE & n.het.g == sat.groups & het == dem & het.g == d,][["Estimate"]]
          
          ## Estimate the matrix of the implied system of equations
          if (n.g > 1) {
            # Get the empirical distribution of prices by quantile
            sample[, base.sales.q := base.sales/sum(base.sales), by = .(quantile)]
            sample[, p_group := floor((dm.ln_cpricei2 - min(dm.ln_cpricei2, na.rm = T))/((max(dm.ln_cpricei2, na.rm = T)-min(dm.ln_cpricei2, na.rm = T))/500)), by = .(quantile)]
            sample[, p_ll := p_group*((max(dm.ln_cpricei2, na.rm = T)-min(dm.ln_cpricei2, na.rm = T))/500), by = .(quantile)]
            sample[, p_ll := p_ll + min(dm.ln_cpricei2, na.rm = T), by = .(quantile)]
            sample[, p_ul := p_ll + ((max(dm.ln_cpricei2, na.rm = T)-min(dm.ln_cpricei2, na.rm = T))/500), by = .(quantile)]
            
            ed.price.quantile <- sample[, .(w1 = (sum(base.sales.q))), by = .(p_ul, p_ll, quantile)]
            ed.price.quantile[, p_m := (p_ul+p_ll)/2]
            
            
            # Create the derivative of the polynomial of prices and multiplicate by weights
            for (n in 1:n.g){
              ed.price.quantile[, paste0("b",n) := (n)*w1*(p_m^(n-1))]
            }
            # Calculate integral
            gamma <- ed.price.quantile[ , lapply(.SD, sum), by = .(quantile), .SDcols = paste0("b",1:n.g)]
            gamma <- gamma[!is.na(quantile),][order(quantile)][, -c("quantile")]
            
            ## Retrieve target parameters
            beta_hat <- as.vector(solve(as.matrix(gamma))%*%(as.matrix(IV)))
            # Estimate intercept
            mean.q <- all_pi[, mean(ln_quantity3, weights = base.sales)]
            mean.p <- all_pi[, mean(dm.ln_cpricei2, weights = base.sales)]
            beta_0_hat <- mean.q - sum((beta_hat)*(mean.p^(1:n.g)))
            beta_hat <- c(beta_0_hat, beta_hat)
            
            ## Export estimated target parameters
            estimated.target <- data.table(beta_hat)
            estimated.target[, beta_n := .I-1]
            estimated.target[, n.groups := n.g]
            estimated.target[, controls := FE]
            estimated.target[, het := dem]
            estimated.target[, het.g := d]
            estimated.target[, n.het.g := sat.groups]
            estimated.target[, P.het.d := prop]
            
            
            target_res <- rbind(target_res, estimated.target)
            fwrite(target_res, theta.results.file)
          }
        }  
      }
    }
  }
}

  


