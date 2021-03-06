#' Sales Tax Project
#' Retailer data
#' Estimate Propensity Score of the effect of sales taxes using a binary treatment
#' Estimate yearly: treatment status varies (each year high or low depends on yearly median)
#' Use selection equation specification suggested by Imbens (C_lin = 1 and C_qua = 2.71)
#' Try different "matching" algorithms: remember we are matching at countly level
#' 

library(data.table)
library(lfe)
library(futile.logger)
library(AER)
library(multcomp)
library(psych)
library(ggplot2)
library(DescTools)

# Set directory

setwd("/project2/igaarder")

## useful filepaths ------------------------------------------------------------
all_goods_pi_path <- "Data/Nielsen/price_quantity_indices_allitems_2006-2016_notaxinfo.csv"
FE_pindex_path <- "Data/Nielsen/Pindex_FE_yearly_all_years.csv"
output_yearly <- "Data/Nielsen/yearly_nielsen_data.csv"
pre_trend_data_path <- "Data/Nielsen/pre_trend_data_yearly.csv"

covariates.nhgis.path <- "Data/covariates/nhgis_county_clean.csv"
covariates.qcew.path <- "Data/covariates/qcew_clean.csv"
census.regions.path <- "Data/covariates/census_regions.csv"

tax.path <- "Data/county_monthly_tax_rates_2008_2014.csv"

zillow_path <- "Data/covariates/zillow_long_by_county_clean.csv"
zillow_state_path <- "Data/covariates/zillow_long_by_state_clean.csv"
unemp.path <- "Data/covariates/county_monthly_unemp_clean.csv"
border.path <- "Data/border_counties.csv"

## Where to save results
output.decriptives.file <- "../../home/slacouture/PS/describe_check.csv"
output.results.file <- "../../home/slacouture/PS/PS_LRspec_crosssection_binarypscore.csv"
output.path <- "../../home/slacouture/PS"
comp.output.results.file <- "../../home/slacouture/PS/sum_PS_LRspec_crosssection_binarypscore.csv"

###### County covariates set up. I keep every possible covariate -----------------------------
# Need to load yearly data to identify useful counties
yearly_data <- fread(output_yearly)
## Time invariant covariates
list.counties <- data.table(unique(yearly_data[,c('fips_state','fips_county')]))

#nhgis 2010 
nhgis2010 <- fread(covariates.nhgis.path)
nhgis2010 <- nhgis2010[year == 2010,] ## Keep the 2010 values
nhgis2010 <- nhgis2010[, c("statefp", "countyfp", "pct_pop_over_65", "pct_pop_under_25", "pct_pop_black", "pct_pop_urban", "housing_ownership_share")]
names(nhgis2010) <- c("fips_state", "fips_county", "pct_pop_over_65", "pct_pop_under_25", "pct_pop_black", "pct_pop_urban", "housing_ownership_share")
covariates <- merge(list.counties, nhgis2010, by = c("fips_state", "fips_county"), all.x = T)


#nhgis 2000 (because education and median income variables are missing in 2010)
nhgis2000 <- fread(covariates.nhgis.path)
nhgis2000 <- nhgis2000[year == 2000,] ## Keep the 2000 values
nhgis2000 <- nhgis2000[, c("statefp", "countyfp", "pct_pop_no_college", "pct_pop_bachelors", "median_income")]
names(nhgis2000) <- c("fips_state", "fips_county", "pct_pop_no_college", "pct_pop_bachelors", "median_income")

nhgis2000[, median_income := log(median_income)]
covariates <- merge(covariates, nhgis2000, by = c("fips_state", "fips_county"), all.x = T)

#census regions/divisions
census.regions <- fread(census.regions.path)
census.regions[, Division := Region*10 + Division]
covariates <- merge(covariates, census.regions, by = c("fips_state"), all.x = T)

## Time variant covariates
list.obs <- data.frame(unique(yearly_data[,c('fips_state','fips_county', 'year')]))
covariates <- merge(list.obs, covariates, by = c("fips_county", "fips_state"), all.x = T)

#qcew
qcew <- fread(covariates.qcew.path)
qcew <- qcew[year >= 2008 & year <= 2014,]
qcew <- qcew[, fips_state := as.numeric(substr(area_fips, 1, 2))]
qcew <- qcew[, fips_county := as.numeric(substr(area_fips, 3, 5))]
qcew <- qcew[, ln_mean_wage := log(total_mean_wage)]
qcew <- qcew[, ln_mean_retail_wage := log(retail_mean_wage)]
qcew <- qcew[, -c("total_mean_wage", "retail_mean_wage" )]
covariates <- merge(covariates, qcew, by = c("year", "fips_county", "fips_state"), all.x = T)


#Zillow
all_counties <- unique(yearly_data[, .(fips_state, fips_county)])
county_skeleton <- data.table(NULL)
for (X in 2008:2014) {
  for (Y in 1:12) {
    all_counties[, year := X]
    all_counties[, month := Y]
    county_skeleton <- rbind(county_skeleton, all_counties)
  }
}


zillow_dt <- fread(zillow_path)
zillow_dt <- zillow_dt[between(year, 2008, 2014)]
zillow_dt <- zillow_dt[, .(fips_state, fips_county, median_home_price, year, month)]
zillow_dt <- merge(county_skeleton, zillow_dt, all.x = T,
                   by = c("fips_state", "fips_county", "year", "month"))

## prep state-level house prices (for when county-level is missing)
zillow_state_dt <- fread(zillow_state_path)
zillow_state_dt <- zillow_state_dt[between(year, 2008, 2014)]
zillow_state_dt <- zillow_state_dt[, .(fips_state, median_home_price, year, month)]
setnames(zillow_state_dt, "median_home_price", "state_median_home_price")
zillow_state_dt$month <- as.integer(round(zillow_state_dt$month))

zillow_dt <- merge(zillow_dt, zillow_state_dt, all.x = T,
                   by = c("fips_state", "year", "month"))
zillow_dt[is.na(median_home_price), median_home_price := state_median_home_price]
zillow_dt[, state_median_home_price := NULL]


## collapse to years
zillow_dt <- zillow_dt[, list(ln_home_price = log(mean(median_home_price))),
                       by = .(year, fips_state, fips_county)]
covariates <- merge(covariates, zillow_dt, by = c("year", "fips_county", "fips_state"), all.x = T)


### Unemployment data
unemp.data <- fread(unemp.path)
unemp.data <- unemp.data[, c("fips_state", "fips_county", "year", "month", "rate")]
unemp.data <- unemp.data[, list(unemp = mean(rate)), by = .(year, fips_state, fips_county)]
unemp.data <- unemp.data[year >= 2006 & year <= 2016,]
unemp.data <- unemp.data[, ln_unemp := log(unemp)]
unemp.data <- unemp.data[, -c("rate", "unemp")]

covariates <- merge(covariates, unemp.data, by = c("year", "fips_county", "fips_state"), all.x = T)

#### tax rates

tax.data <- fread(tax.path)
tax.data <- tax.data[, list(sales_tax = mean(sales_tax, na.rm = T)), by = .(year, fips_state, fips_county)]
tax.data <- tax.data[, ln_sales_tax := log1p(sales_tax)]

covariates <- merge(covariates, tax.data, by = c("year", "fips_county", "fips_state"), all.x = T)

covariates <- as.data.table(covariates)
yearly_data <- as.data.table(yearly_data)
# Got to drop some variables in yearly data to perform well
yearly_data <- yearly_data[, -c("n", "yr", "sales_tax")]
# Create Share of quantities
yearly_data <- yearly_data[, ln_share_sales := log(sales/sum(sales)), 
                           by = .(store_code_uc, fips_county, fips_state, year)]

###### Propensity Score set up -----------------------------

# Vector of "must be in" variables
Xb <- c("ln_unemp", "ln_home_price")

# Vector of potential variables
Xa_pot <- c("pct_pop_urban", "housing_ownership_share", "median_income", "pct_pop_no_college", "pct_pop_bachelors",
            "pct_pop_over_65", "pct_pop_under_25", "pct_pop_black", "ln_mean_wage")

# Vector of all variables
X_all <- c(Xb, Xa_pot)


# Vector of outcomes to run cross-sectional design. Not gonna run on covariates: already balancing on them at county level
outcomes <- c("ln_cpricei2", "ln_quantity2", "ln_share_sales", "ln_sales_tax", "ln_statutory_sales_tax")


###### Run Estimation ------------------------------------
# Start yearly loop
LRdiff_res <- data.table(NULL)
for (yr in 2008:2014) {
  
  flog.info("Starting year %s", yr)
  # Keep year of interest
  year.data <- yearly_data[ year == yr, ]
  year.covariates <- covariates[ year == yr, ]
  # Create binary treatment. Drop first counties without tax data
  year.covariates <- year.covariates[!is.na(ln_sales_tax), ]
  year.covariates <- year.covariates[, high.tax.rate := (ln_sales_tax >= median(ln_sales_tax)) ]
  year.data <- year.data[, taxable :=ifelse(ln_sales_tax == 0, FALSE, TRUE)]
  # Compute average difference in sales tax between groups to report afterwards
  difference <- year.covariates[ high.tax.rate == T][, mean(exp(ln_sales_tax))] - year.covariates[ high.tax.rate == F][, mean(exp(ln_sales_tax))]
  
  ### Selection of covariates. Algorithm suggested by Imbens (2015) -----
  # Basic regression
  RHS <- paste(Xb, collapse  = " + ")
  curr.formula <- paste0("high.tax.rate ~ ", RHS)
  basic.select <- glm(curr.formula, family = binomial(link = "logit"), 
                      data = year.covariates, maxit = 10000)
  curr.likelihood <- basic.select$deviance
  reference <- nrow(year.covariates)
  
  # Selection of linear covariates to add (C_lin = 1 and logit)
  C_lin <- 1 # Threshold value
  Xblin <- Xb
  for (X in Xa_pot) {
    
    # Capture n_obs of potential variable
    N <- nrow(year.covariates[!is.na(get(X))])
    ratio.attr <- N/reference 
    # Try only those in which we lose less than 2% of the sample
    if (ratio.attr > 0.98) {
      new.formula <- paste(curr.formula, X, sep = " + ")
      # Run logit
      new.select <- glm(new.formula, family = binomial(link = "logit"), 
                        data = year.covariates, maxit = 10000) 
      # Use if likelihood test is above threshold
      lr.test <- (curr.likelihood - new.select$deviance)
      if (lr.test > C_lin) {
        # Capture
        curr.formula <- new.formula
        curr.likelihood <- new.select$deviance
        new <- paste0(X)
        Xblin = c(Xblin, new)
      }
    }
  }
  
  # Selection of quadratic covariates to add (C_qua = 2.71 and logit)
  C_qua <- 2.71 # Threshold value
  dim <- length(Xblin)
  row <- 0
  col <- 0
  Xfinal <- Xblin
  for (X1 in Xblin) {
    row <- row + 1
    for (X2 in Xb) {
      col <- col + 1
      t <- row + col + 1
      # Function to avoid repetition
      if (t <= dim) {
        # create product
        X <- paste(X1, X2, sep = "_")
        if (X1 == X2) {X <- paste0(X1, "_2")}
        year.covariates <- year.covariates[ , (X) := (get(X1)) * (get(X2))]
        new.formula <- paste(curr.formula, X, sep = " + ")
        new.select <- glm(new.formula, family = binomial(link = "logit"), 
                          data = year.covariates, maxit = 10000)  
        lr.test <- (curr.likelihood - new.select$deviance)
        if (lr.test > C_qua) {
          # Capture
          curr.formula <- new.formula
          curr.likelihood <- new.select$deviance
          Xfinal = c(Xfinal, X)
        } else {
          
          year.covariates <- year.covariates[, (X) := NULL ]
          
        }
        
      }  
      
    }
    
  }
  
  flog.info("Selection equation for year %s is: %s", yr, curr.formula)
  # Run the chosen selection equation
  final.select <- glm(curr.formula, family = binomial(link = "logit"), 
                      data = year.covariates, maxit = 10000)
  
  ### Trim Sample: we choose to trim by "Sufficient Overlap" as in Imbens (2015) -------
  # Following their approach, we use the practical choise of alpha = 0.1 an thus 
  # A = {x in X | 0.1 <= e(x) <= 0.9}
  # Predict and dropping sales tax rates (not used any more and want to use the effective tax rate)
  year.covariates[, pscore:= predict(final.select, year.covariates, type = "response")]
  # Drop tax rate in county level (we need both effective and statutory tax rate)
  setnames(year.covariates, old = "ln_sales_tax", new = "ln_statutory_sales_tax")
  # trimming 
  year.covariates.trim <- year.covariates[pscore >= 0.1 & pscore <= 0.9 & !is.na(pscore)]
  
  #### Now create comparision samples. Use 4 different algorithms ----------- 
  # 1) nearest neighbord, 2) k-nearest, 3) caliper, 4) weighted

    flog.info("Running matching algorithms for year %s", yr)
  # Algorithm 1: nearest neighbor (with replacement). All units are matched, both treated and controls
  nn.crosswalk <-data.table(NULL)
  for (i in 1:nrow(year.covariates.trim)) {
    
    # Extract observation info
    obs.i <- year.covariates.trim[i, ]
    # Add Info of pair number
    obs.i <- obs.i[, n_pair := i]
    # Find potential pairs and order by distance to selected observation
    potential.pairs <- year.covariates.trim[high.tax.rate != obs.i[, high.tax.rate], 
                                            ][, distance := abs(pscore - obs.i[, pscore])][order(distance)]
    # Extract closest pair
    pair.i<- potential.pairs[1, ][, -c("distance")]
    pair.i <- pair.i[, n_pair := i]
    # paste to previous selected pairs
    nn.crosswalk <- rbind(nn.crosswalk, obs.i, pair.i)
  }
  
  # Algorithm 2: k-nearest neighbor (with replacement). k=3. All units are matched, both treated and controls
  knn.crosswalk <-data.table(NULL)
  for (i in 1:nrow(year.covariates.trim)) {
    
    # Extract observation info
    obs.i <- year.covariates.trim[i, ]
    # Add Info of pair number
    obs.i <- obs.i[, n_pair := i][, w := 1]
    # Find potential pairs and order by distance to selected observation
    potential.pairs <- year.covariates.trim[high.tax.rate != obs.i[, high.tax.rate],
                                            ][, distance := abs(pscore - obs.i[, pscore])][order(distance)]
    # Extract closest pair
    pair.i<- potential.pairs[1:3, ][, -c("distance")]
    pair.i <- pair.i[, n_pair := i][, w := 1/3]
    # paste to previous selected pairs
    knn.crosswalk <- rbind(knn.crosswalk, obs.i, pair.i)
  }
  
  # Algorithm 3: neighbors in caliper (with replacement). r=0.001. All units are matched, both treated and controls. 
  # Note: If no pairfound, drop
  calip.crosswalk <-data.table(NULL)
  r <- 0.001 # Define caliper ratio
  for (i in 1:nrow(year.covariates.trim)) {
    
    # Extract observation info
    obs.i <- year.covariates.trim[i, ]
    # Add Info of pair number
    obs.i <- obs.i[, n_pair := i][, w := 1]
    # Find potential pairs and order by distance to selected observation
    potential.pairs <- year.covariates.trim[high.tax.rate != obs.i[, high.tax.rate],
                                            ][, distance := abs(pscore - obs.i[, pscore])][order(distance)]
    # Extract closest pair
    pair.i<- potential.pairs[distance < r, ][, -c("distance")]
    # PErform if pair found
    if (nrow(pair.i) > 0) {
      pair.i <- pair.i[, n_pair := i][, w := 1/.N]
      # paste to previous selected pairs
      calip.crosswalk <- rbind(calip.crosswalk, obs.i, pair.i)
    }
  }
  
  # Algorithm 4: weighting estimator. Build weights
  weighted.crosswalk <- year.covariates.trim[, w := ifelse(high.tax.rate == T, 
                                                           sum(high.tax.rate)*sum(high.tax.rate/pscore)/pscore,
                                                           sum(1-high.tax.rate)*sum((1-high.tax.rate)/(1-pscore))/(1-pscore)
  )]
  
  
  ##### Check balance using basic regression tests on covariates (Xfinal) by algorithm -------
  flog.info("Checking balance for year %s", yr)
  test.year <- data.table(NULL)
  for (X in Xfinal) {
    
    # Rowname
    outcome <-data.table(X)
    setnames(outcome, old = c("X"), new = c("outcome"))
    # Prior balance
    test.out <- lm(get(X) ~ high.tax.rate, data = year.covariates)
    priortest.dt <- data.table(coef(summary(test.out)))[2,][, -c("t value")]
    setnames(priortest.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("prior.est", "prior.std.err", "prior.pval"))
    # Adjusted nn balance
    nn.test.out <- lm(get(X) ~ high.tax.rate, data = nn.crosswalk)
    nn.test.dt <- data.table(coef(summary(nn.test.out)))[2,][, -c("t value")]
    setnames(nn.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("nn.est", "nn.std.err", "nn.pval"))
    # Adjusted knn balance
    knn.test.out <- lm(get(X) ~ high.tax.rate, data = knn.crosswalk, weights = w)
    knn.test.dt <- data.table(coef(summary(knn.test.out)))[2,][, -c("t value")]
    setnames(knn.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("knn.est", "knn.std.err", "knn.pval"))
    # Adjusted caliper balance
    calip.test.out <- lm(get(X) ~ high.tax.rate, data = calip.crosswalk, weights = w)
    calip.test.dt <- data.table(coef(summary(calip.test.out)))[2,][, -c("t value")]
    setnames(calip.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("calip.est", "calip.std.err", "calip.pval"))
    # Adjusted caliper balance
    weight.test.out <- lm(get(X) ~ high.tax.rate, data = weighted.crosswalk, weights = w)
    weight.test.dt <- data.table(coef(summary(weight.test.out)))[2,][, -c("t value")]
    setnames(weight.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("weight.est", "weight.std.err", "weight.pval"))
    # Merge all tests
    test.dt <- cbind(outcome, priortest.dt, nn.test.dt, knn.test.dt, calip.test.dt, weight.test.dt)
    
    flog.info("Balance check for %s done", X)
    # Append to other outcomes
    test.year <- rbind(test.year, test.dt, fill = T)
  }
  ##### Check balance using basic regression tests on all covariates (X_all) by algorithm -------
  test.year <- data.table(NULL)
  for (X in X_all) {
    
    # Rowname
    outcome <-data.table(X)
    setnames(outcome, old = c("X"), new = c("outcome"))
    # Prior balance
    test.out <- lm(get(X) ~ high.tax.rate, data = year.covariates)
    priortest.dt <- data.table(coef(summary(test.out)))[2,][, -c("t value")]
    setnames(priortest.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("prior.est", "prior.std.err", "prior.pval"))
    # Adjusted nn balance
    nn.test.out <- lm(get(X) ~ high.tax.rate, data = nn.crosswalk)
    nn.test.dt <- data.table(coef(summary(nn.test.out)))[2,][, -c("t value")]
    setnames(nn.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("nn.est", "nn.std.err", "nn.pval"))
    # Adjusted knn balance
    knn.test.out <- lm(get(X) ~ high.tax.rate, data = knn.crosswalk, weights = w)
    knn.test.dt <- data.table(coef(summary(knn.test.out)))[2,][, -c("t value")]
    setnames(knn.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("knn.est", "knn.std.err", "knn.pval"))
    # Adjusted caliper balance
    calip.test.out <- lm(get(X) ~ high.tax.rate, data = calip.crosswalk, weights = w)
    calip.test.dt <- data.table(coef(summary(calip.test.out)))[2,][, -c("t value")]
    setnames(calip.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("calip.est", "calip.std.err", "calip.pval"))
    # Adjusted caliper balance
    weight.test.out <- lm(get(X) ~ high.tax.rate, data = weighted.crosswalk, weights = w)
    weight.test.dt <- data.table(coef(summary(weight.test.out)))[2,][, -c("t value")]
    setnames(weight.test.dt, old = c("Estimate", "Std. Error", "Pr(>|t|)"),
             new = c("weight.est", "weight.std.err", "weight.pval"))
    # Merge all tests
    test.dt <- cbind(outcome, priortest.dt, nn.test.dt, knn.test.dt, calip.test.dt, weight.test.dt)
    
    flog.info("Balance check for %s done", X)
    # Append to other outcomes
    test.year <- rbind(test.year, test.dt, fill = T)
  }  
  # Export yearly test
  test.year.outfile <- paste0(output.path, "/Cov.Test/all_covariate_balance_", yr, ".csv")
  fwrite(test.year, test.year.outfile)
  
  #### Estimate cross-sectional design for each algorithm -------
  flog.info("Running estimates for year %s", yr)
  
  
  #### No-matching coefficients
  
  # Merge data
  year.covariates <- merge(year.data, year.covariates, by = c("fips_state", "fips_county", "year"))
  year.covariates <- data.table(year.covariates)
  # Create Interaction term
  year.covariates <- year.covariates[, high.tax.rate_taxable := high.tax.rate*taxable]
  # Make sure there are no 0 weights
  year.covariates <- year.covariates[!is.na(base.sales)]
  year.covariates <- year.covariates[, curr.sales := sales]  
  for(Y in outcomes) {
    
    formula0 <- as.formula(paste0(
      Y, " ~ high.tax.rate + taxable + high.tax.rate_taxable | product_module_code | 0 | state_by_module ", sep = ""
    ))
    
    flog.info("Estimating %s...", Y)
    ### Base weights
    res0 <- felm(data = year.covariates,
                 formula = formula0,
                 weights = year.covariates$base.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "NoMatch"]
    res1.dt[, weight := "base.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(year.covariates)]
    res1.dt[, N_modules := length(unique(year.covariates$product_module_code))]
    res1.dt[, N_stores := length(unique(year.covariates$store_code_uc))]
    res1.dt[, N_counties := uniqueN(year.covariates, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(year.covariates, by = c("fips_state", "fips_county",
                                                               "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(year.covariates, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(year.covariates, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file 
    
    
    ### Current weights
    res0 <- felm(data = year.covariates,
                 formula = formula0,
                 weights = year.covariates$curr.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "NoMatch"]
    res1.dt[, weight := "curr.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(year.covariates)]
    res1.dt[, N_modules := length(unique(year.covariates$product_module_code))]
    res1.dt[, N_stores := length(unique(year.covariates$store_code_uc))]
    res1.dt[, N_counties := uniqueN(year.covariates, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(year.covariates, by = c("fips_state", "fips_county",
                                                               "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(year.covariates, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(year.covariates, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file
    
  }  
  
  
  
  #### Algorithm 1: Nearest Neighbord
  nn.crosswalk <- merge(year.data, nn.crosswalk, by = c("fips_state", "fips_county", "year"), allow.cartesian=TRUE)
  nn.crosswalk <- data.table(nn.crosswalk)
  # Create Interaction term
  nn.crosswalk <- nn.crosswalk[, high.tax.rate_taxable := high.tax.rate*taxable]
  # Make sure there are no 0 weights
  nn.crosswalk <- nn.crosswalk[!is.na(base.sales)]
  nn.crosswalk <- nn.crosswalk[, curr.sales := sales]

  for(Y in outcomes) {
    
    formula0 <- as.formula(paste0(
      Y, " ~ high.tax.rate + taxable + high.tax.rate_taxable | product_module_code | 0 | state_by_module ", sep = ""
    ))
    
    flog.info("Estimating %s...", Y)
    ### Base weights
    res0 <- felm(data = nn.crosswalk,
                 formula = formula0,
                 weights = nn.crosswalk$base.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "NN"]
    res1.dt[, weight := "base.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(nn.crosswalk)]
    res1.dt[, N_modules := length(unique(nn.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(nn.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(nn.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(nn.crosswalk, by = c("fips_state", "fips_county",
                                                               "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(nn.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(nn.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file 
    
    
    ### Current weights
    res0 <- felm(data = nn.crosswalk,
                 formula = formula0,
                 weights = nn.crosswalk$curr.sales)

    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "NN"]
    res1.dt[, weight := "curr.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(nn.crosswalk)]
    res1.dt[, N_modules := length(unique(nn.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(nn.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(nn.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(nn.crosswalk, by = c("fips_state", "fips_county",
                                                                  "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(nn.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(nn.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file
    
  }

  #### Algorithm 2: k-Nearest Neighbord
  knn.crosswalk <- merge(year.data, knn.crosswalk, by = c("fips_state", "fips_county", "year"), allow.cartesian=TRUE)
  # Create Interaction term
  knn.crosswalk <- knn.crosswalk[, high.tax.rate_taxable := high.tax.rate*taxable]
  # Create new weights
  knn.crosswalk <- knn.crosswalk[, base.sales := base.sales*w]
  knn.crosswalk <- knn.crosswalk[, curr.sales := sales*w]
  # Make sure there are no 0 weights
  knn.crosswalk <- knn.crosswalk[!is.na(base.sales)]
  
  for(Y in outcomes) {
    
    
    formula0 <- as.formula(paste0(
      Y, " ~ high.tax.rate + taxable + high.tax.rate_taxable | product_module_code | 0 | state_by_module ", sep = ""
    ))
    flog.info("Estimating %s...", Y)
    ### Base weights
    res0 <- felm(data = knn.crosswalk,
                 formula = formula0,
                 weights = knn.crosswalk$base.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "KNN"]
    res1.dt[, weight := "base.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(knn.crosswalk)]
    res1.dt[, N_modules := length(unique(knn.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(knn.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(knn.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(knn.crosswalk, by = c("fips_state", "fips_county",
                                                                "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(knn.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(knn.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file 
    
    
    ### Current weights
    res0 <- felm(data = knn.crosswalk,
                 formula = formula0,
                 weights = knn.crosswalk$curr.sales)

    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "KNN"]
    res1.dt[, weight := "curr.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(knn.crosswalk)]
    res1.dt[, N_modules := length(unique(knn.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(knn.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(knn.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(knn.crosswalk, by = c("fips_state", "fips_county",
                                                                "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(knn.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(knn.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file
    
  }
  
  #### Algorithm 3: Caliper
  calip.crosswalk <- merge(year.data, calip.crosswalk, by = c("fips_state", "fips_county", "year"), allow.cartesian=TRUE)
  # Create Interaction term
  calip.crosswalk <- calip.crosswalk[, high.tax.rate_taxable := high.tax.rate*taxable]
  # Create new weights
  calip.crosswalk <- calip.crosswalk[, base.sales := base.sales*w]
  calip.crosswalk <- calip.crosswalk[, curr.sales := sales*w]
  # Make sure there are no 0 weights
  calip.crosswalk <- calip.crosswalk[!is.na(base.sales) & !is.na(curr.sales)]
  
  for(Y in outcomes) {
    
    
    formula0 <- as.formula(paste0(
      Y, " ~ high.tax.rate + taxable + high.tax.rate_taxable | product_module_code | 0 | state_by_module ", sep = ""
    ))
    flog.info("Estimating %s...", Y)
    ### Base weights
    res0 <- felm(data = calip.crosswalk,
                 formula = formula0,
                 weights = calip.crosswalk$base.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "Caliper"]
    res1.dt[, weight := "base.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(calip.crosswalk)]
    res1.dt[, N_modules := length(unique(calip.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(calip.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(calip.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(calip.crosswalk, by = c("fips_state", "fips_county",
                                                                  "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(calip.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(calip.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file 
    
    
    ### Current weights
    res0 <- felm(data = calip.crosswalk,
                 formula = formula0,
                 weights = calip.crosswalk$curr.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "Caliper"]
    res1.dt[, weight := "curr.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(calip.crosswalk)]
    res1.dt[, N_modules := length(unique(calip.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(calip.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(calip.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(calip.crosswalk, by = c("fips_state", "fips_county",
                                                                "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(calip.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(calip.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file
    
  }

  
  #### Algorithm 4: Weighted estimation
  weighted.crosswalk <- merge(year.data, weighted.crosswalk, by = c("fips_state", "fips_county", "year"))
  # Create Interaction term
  weighted.crosswalk <- weighted.crosswalk[, high.tax.rate_taxable := high.tax.rate*taxable]
  # Create new weights
  weighted.crosswalk <- weighted.crosswalk[, base.sales := base.sales*w]
  weighted.crosswalk <- weighted.crosswalk[, curr.sales := sales*w]
  
  # Make sure there are no 0 weights
  weighted.crosswalk <- weighted.crosswalk[!is.na(base.sales) & !is.na(curr.sales)]

  for(Y in outcomes) {
    
    
    formula0 <- as.formula(paste0(
      Y, " ~ high.tax.rate + taxable + high.tax.rate_taxable | product_module_code | 0 | state_by_module ", sep = ""
    ))
    flog.info("Estimating %s...", Y)
    ### Base weights
    res0 <- felm(data = weighted.crosswalk,
                 formula = formula0,
                 weights = weighted.crosswalk$base.sales)
    
    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "Weighted"]
    res1.dt[, weight := "base.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(weighted.crosswalk)]
    res1.dt[, N_modules := length(unique(weighted.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(weighted.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(weighted.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(weighted.crosswalk, by = c("fips_state", "fips_county",
                                                                     "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(weighted.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(weighted.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file 
    
    
    ### Current weights
    res0 <- felm(data = weighted.crosswalk,
                 formula = formula0,
                 weights = weighted.crosswalk$curr.sales)

    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res0)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, Rsq := summary(res0)$r.squared]
    res1.dt[, adj.Rsq := summary(res0)$adj.r.squared]
    res1.dt[, specification := "Weighted"]
    res1.dt[, weight := "curr.sales"]
    res1.dt[, year := yr]
    res1.dt[, av.tax.diff := difference]
    res1.dt[, N_obs := nrow(weighted.crosswalk)]
    res1.dt[, N_modules := length(unique(weighted.crosswalk$product_module_code))]
    res1.dt[, N_stores := length(unique(weighted.crosswalk$store_code_uc))]
    res1.dt[, N_counties := uniqueN(weighted.crosswalk, by = c("fips_state", "fips_county"))]
    res1.dt[, N_county_modules := uniqueN(weighted.crosswalk, by = c("fips_state", "fips_county",
                                                                "product_module_code"))]
    res1.dt[, N_store_modules := uniqueN(weighted.crosswalk, by = c("store_code_uc", "product_module_code"))]
    res1.dt[, N_state_modules := uniqueN(weighted.crosswalk, by = c("fips_state", "product_module_code"))]
    LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
    fwrite(LRdiff_res, output.results.file)  ## Write results to a csv file
    
  }

}


##### Produce interest information of estimates in a separate file -----

### Capture specific coeficients within year
c1 <- LRdiff_res[rn == "taxableTRUE", ][, -c("Cluster s.e.", "t value", "Pr(>|t|)")]
c2 <- LRdiff_res[rn == "taxableTRUE" | rn == "high.tax.rate_taxable",][, list(Estimate = sum(Estimate)), 
                                                                       by = .(outcome, Rsq,	adj.Rsq, specification,
                                                                              weight,	year,	av.tax.diff, N_obs,	N_modules, 
                                                                              N_stores, N_counties, N_county_modules,
                                                                              N_store_modules, N_state_modules) ][, rn := "taxableTRUE + high.tax.rate_taxable"]
c3 <- LRdiff_res[rn == "taxableTRUE" | rn == "high.tax.rate_taxable",][, list(Estimate = mean(Estimate)), 
                                                                       by = .(outcome, Rsq,	adj.Rsq, specification,
                                                                              weight,	year,	av.tax.diff, N_obs,	N_modules, 
                                                                              N_stores, N_counties, N_county_modules,
                                                                              N_store_modules, N_state_modules) ][, rn := "(taxableTRUE + high.tax.rate_taxable)/2"]

c4 <- LRdiff_res[rn == "high.tax.rateTRUE" | rn == "high.tax.rate_taxable",][, list(Estimate = sum(Estimate)), 
                                                                             by = .(outcome, Rsq,	adj.Rsq, specification,
                                                                                    weight,	year,	av.tax.diff, N_obs,	N_modules, 
                                                                                    N_stores, N_counties, N_county_modules,
                                                                                    N_store_modules, N_state_modules) ][, rn := "high.tax.rateTRUE + high.tax.rate_taxable"]
c5 <- LRdiff_res[rn == "high.tax.rate_taxable", ][, -c("Cluster s.e.", "t value", "Pr(>|t|)")]
### Paste and compute estimates across years
PS_res <- rbind(c1, c2, c3, c4, c5)

c6 <- PS_res[, list(Estimate = mean(Estimate)), 
             by = .(rn, outcome, specification, weight) ]
# Renames
c6[rn == "taxableTRUE", rn := "Av.taxableTRUE"]
c6[rn == "taxableTRUE + high.tax.rate_taxable", rn := "Av.(taxableTRUE + high.tax.rate_taxable)"]
c6[rn == "(taxableTRUE + high.tax.rate_taxable)/2", rn := "Av.(taxableTRUE + high.tax.rate_taxable)/2"]
c6[rn == "high.tax.rateTRUE + high.tax.rate_taxable", rn := "Av.(high.tax.rateTRUE + high.tax.rate_taxable)"]
c6[rn == "high.tax.rate_taxable", rn := "Av.high.tax.rate_taxable"]

# Append
PS_res <- rbind(PS_res, c6, fill = T)
PS_res <- PS_res[order(year, specification, outcome, weight),]

## Export
fwrite(PS_res, comp.output.results.file)  ## Write results to a csv file


