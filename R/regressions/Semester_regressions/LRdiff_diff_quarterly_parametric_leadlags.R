#' Author: John Bonney
#'
#' Address to-do items sent to me from Lance on June 4, 2019.

library(data.table)
library(futile.logger)
library(lfe)
library(multcomp)

setwd("/project2/igaarder")


## input filepaths -----------------------------------------------
#' This data set contains quarterly Laspeyres indices and sales from 2006 to
#' 2014. It also contains sales tax rates from 2008-2014.
all_goods_pi_path <- "Data/Nielsen/price_quantity_indices_allitems_2006-2016_notaxinfo.csv"
#' This data set contains an old price index that Lance constructed, from
old_pi_path <- "Data/Nielsen/Quarterly_old_pi.csv"
#' This data is the same as all_goods_pi_path, except it has 2015-2016 data as well.
data.full.path <- "Data/all_nielsen_data_2006_2016_quarterly.csv"

zillow_path <- "Data/covariates/zillow_long_by_county_clean.csv"
zillow_state_path <- "Data/covariates/zillow_long_by_state_clean.csv"
unemp.path <- "Data/covariates/county_monthly_unemp_clean.csv"

## output filepaths ----------------------------------------------
output.results.file <- "Data/LRdiff_quarterly_results_parametric_leadlags.csv"


## prep Census region/division data ------------------------------
geo_dt <- structure(list(
  fips_state = c(1L, 2L, 4L, 5L, 6L, 8L, 9L, 10L, 12L, 13L, 15L, 16L, 17L, 18L,
                 19L, 20L, 21L, 22L, 23L, 24L, 25L, 26L, 27L, 28L, 29L, 30L,
                 31L, 32L, 33L, 34L, 35L, 36L, 37L, 38L, 39L, 40L, 41L, 42L,
                 44L, 45L, 46L, 47L, 48L, 49L, 50L, 51L, 53L, 54L, 55L, 56L),
  region = c(3L, 4L, 4L, 3L, 4L, 4L, 1L, 3L, 3L, 3L, 4L, 4L, 2L, 2L, 2L, 2L, 3L,
             3L, 1L, 3L, 1L, 2L, 2L, 3L, 2L, 4L, 2L, 4L, 1L, 1L, 4L, 1L, 3L, 2L,
             2L, 3L, 4L, 1L, 1L, 3L, 2L, 3L, 3L, 4L, 1L, 3L, 4L, 3L, 2L, 4L),
  division = c(6L, 9L, 8L,  7L, 9L, 8L, 1L, 5L, 5L, 5L, 9L, 8L, 3L, 3L, 4L, 4L,
               6L, 7L, 1L, 5L, 1L, 3L, 4L, 6L, 4L, 8L, 4L, 8L, 1L, 2L, 8L, 2L,
               5L, 4L, 3L,  7L, 9L, 2L, 1L, 5L, 4L, 6L, 7L, 8L, 1L, 5L, 9L, 5L, 3L, 8L)),
  class = "data.frame", row.names = c(NA, -50L))
setDT(geo_dt)


##### Load the quarterly price index and sales data (prep/clean them later)
all_pi <- fread(data.full.path)



#### Prep the unemployment and house price data --------------------------
### Start with house prices
# First build a frame to make sure we can assign every county a home price
all_counties <- unique(all_pi[, .(fips_state, fips_county)])
county_skeleton <- data.table(NULL)
for (X in 2006:2016) {
  for (Y in 1:12) {
    all_counties[, year := X]
    all_counties[, month := Y]
    county_skeleton <- rbind(county_skeleton, all_counties)
  }
}

## prep house price data
zillow_dt <- fread(zillow_path)
zillow_dt <- zillow_dt[between(year, 2006, 2016)]
zillow_dt <- zillow_dt[, .(fips_state, fips_county, median_home_price, year, month)]
zillow_dt <- merge(county_skeleton, zillow_dt, all.x = T,
                   by = c("fips_state", "fips_county", "year", "month"))

## prep state-level house prices (for when county-level is missing)
zillow_state_dt <- fread(zillow_state_path)
zillow_state_dt <- zillow_state_dt[between(year, 2006, 2016)]
zillow_state_dt <- zillow_state_dt[, .(fips_state, median_home_price, year, month)]
setnames(zillow_state_dt, "median_home_price", "state_median_home_price")
zillow_state_dt$month <- as.integer(round(zillow_state_dt$month))

zillow_dt <- merge(zillow_dt, zillow_state_dt, all.x = T,
                   by = c("fips_state", "year", "month"))
zillow_dt[is.na(median_home_price), median_home_price := state_median_home_price]
zillow_dt[, state_median_home_price := NULL]


## collapse to quarters
zillow_dt <- zillow_dt[, quarter := ceiling((month/12)*4)]
zillow_dt <- zillow_dt[, list(ln_home_price = log(mean(median_home_price))),
                       by = .(year, quarter, fips_state, fips_county)]


##
all_pi <- merge(all_pi, zillow_dt, by = c("fips_state", "fips_county", "year", "quarter"), all.x = T)


### Unemployment data
unemp.data <- fread(unemp.path)
unemp.data <- unemp.data[, c("fips_state", "fips_county", "year", "month", "rate")]
unemp.data <- unemp.data[, quarter := ceiling((month/12)*4)]
unemp.data <- unemp.data[, list(unemp = mean(rate)), by = .(year, quarter, fips_state, fips_county)]
unemp.data <- unemp.data[year >= 2006 & year <= 2016,]
unemp.data <- unemp.data[, ln_unemp := log(unemp)]


##
all_pi <- merge(all_pi, unemp.data, by = c("fips_state", "fips_county", "year", "quarter"), all.x = T)


## prep the 2006-2016 data --------------------------------------- ##NOTE: in this version we do not merge to "old price indices" because they are under construction
#old_pi <- fread(old_pi_path)

## merge on the old price indices
#all_pi <- merge(all_pi, old_pi,
#                     by = c("fips_state", "fips_county", "store_code_uc",
#                            "product_module_code", "year", "quarter"), all = T)
#rm(old_pi)

## merge on the census region/division info
all_pi <- merge(all_pi, geo_dt, by = "fips_state")

# impute tax rates prior to 2008 and after 2014
all_pi[, sales_tax := ifelse(year < 2008, sales_tax[year == 2008 & quarter == 1], sales_tax),
            by = .(store_code_uc, product_module_code)]
all_pi[, sales_tax := ifelse(year > 2014, sales_tax[year == 2014 & quarter == 4], sales_tax),
            by = .(store_code_uc, product_module_code)]

# create necessary variables
all_pi[, ln_cpricei := log(cpricei)]
all_pi[, ln_sales_tax := log(sales_tax)]
all_pi[, ln_quantity := log(sales) - log(pricei)]
all_pi[, store_by_module := .GRP, by = .(store_code_uc, product_module_code)]
all_pi[, cal_time := 4 * year + quarter]
all_pi[, module_by_time := .GRP, by = .(product_module_code, cal_time)]
all_pi[, module_by_state := .GRP, by = .(product_module_code, fips_state)]
all_pi[, region_by_module_by_time := .GRP, by = .(region, product_module_code, cal_time)]
all_pi[, division_by_module_by_time := .GRP, by = .(division, product_module_code, cal_time)]

## get sales weights
all_pi[, base.sales := sales[year == 2008 & quarter == 1],
            by = .(store_code_uc, product_module_code)]

all_pi <- all_pi[!is.na(base.sales) & !is.na(sales) & !is.na(ln_cpricei) &
                             !is.na(ln_sales_tax) & !is.na(ln_quantity)]
#                             & !is.na(ln_quantity2) & !is.na(ln_cpricei2)]

## balance on store-module level
keep_store_modules <- all_pi[, list(n = .N),
                                  by = .(store_code_uc, product_module_code)]
keep_store_modules <- keep_store_modules[n == (2016 - 2005) * 4]

setkey(all_pi, store_code_uc, product_module_code)
setkey(keep_store_modules, store_code_uc, product_module_code)

all_pi <- all_pi[keep_store_modules]
setkey(all_pi, store_code_uc, product_module_code, year, quarter)


#############################################################
## Delete some variables to save memory
all_pi <- all_pi[, c("fips_state", "fips_county", "year", "quarter", "store_code_uc", "product_module_code", "ln_cpricei", "ln_sales_tax", "ln_quantity", "base.sales", "store_by_module", "cal_time", "module_by_time", "module_by_state", "region_by_module_by_time", "division_by_module_by_time", "ln_home_price", "ln_unemp")]


#######################################################
## take first differences of outcomes and treatment
all_pi <- all_pi[order(store_code_uc, product_module_code, cal_time),] ##Sort on store by year-quarter (in ascending order)


all_pi[, D.ln_cpricei := ln_cpricei - shift(ln_cpricei, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_quantity := ln_quantity - shift(ln_quantity, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_sales_tax := ln_sales_tax - shift(ln_sales_tax, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_unemp := ln_unemp - shift(ln_unemp, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_home_price := ln_home_price - shift(ln_home_price, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]


## Create 2 year differences (= 8 quarters)
all_pi[, D2.ln_unemp := ln_unemp - shift(ln_unemp, n=8, type = "lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D2.ln_home_price := ln_home_price - shift(ln_home_price, n=8, type = "lag"),
       by = .(store_code_uc, product_module_code)]



## generate lags and leads of ln_sales_tax
for (lag.val in 1:8) {
  lag.X <- paste0("L", lag.val, ".D.ln_sales_tax")
  all_pi[, (lag.X) := shift(D.ln_sales_tax, n=lag.val, type="lag"),
         by = .(store_code_uc, product_module_code)]

  lead.X <- paste0("F", lag.val, ".D.ln_sales_tax")
  all_pi[, (lead.X) := shift(D.ln_sales_tax, n=lag.val, type="lead"),
         by = .(store_code_uc, product_module_code)]
}


##Create a lead and lag of the 2-year difference in unemployment and home price
all_pi <- all_pi[order(fips_state, fips_county, store_code_uc, product_module_code, year, quarter), c("F8.D2.ln_unemp") := shift(.SD, 8, type = "lead"), .SDcols = "D2.ln_unemp", by = c("fips_state", "fips_county", "store_code_uc", "product_module_code")]
all_pi <- all_pi[order(fips_state, fips_county, store_code_uc, product_module_code, year, quarter), c("L1.D2.ln_unemp") := shift(.SD, 1, type = "lag"), .SDcols = "D2.ln_unemp", by = c("fips_state", "fips_county", "store_code_uc", "product_module_code")]
all_pi <- all_pi[order(fips_state, fips_county, store_code_uc, product_module_code, year, quarter), c("F8.D2.ln_home_price") := shift(.SD, 8, type = "lead"), .SDcols = "D2.ln_home_price", by = c("fips_state", "fips_county", "store_code_uc", "product_module_code")]
all_pi <- all_pi[order(fips_state, fips_county, store_code_uc, product_module_code, year, quarter), c("L1.D2.ln_home_price") := shift(.SD, 1, type = "lag"), .SDcols = "D2.ln_home_price", by = c("fips_state", "fips_county", "store_code_uc", "product_module_code")]


#### Create sum of lag/lead tax rates interacted with lag/lead
## Stupid way to code this

all_pi[, lead.poly0 := F8.D.ln_sales_tax + F7.D.ln_sales_tax + F6.D.ln_sales_tax + F5.D.ln_sales_tax + F4.D.ln_sales_tax + F3.D.ln_sales_tax + F2.D.ln_sales_tax + F1.D.ln_sales_tax ]
all_pi[, lead.poly1 := 8*F8.D.ln_sales_tax + 7*F7.D.ln_sales_tax + 6*F6.D.ln_sales_tax + 5*F5.D.ln_sales_tax + 4*F4.D.ln_sales_tax + 3*F3.D.ln_sales_tax + 2*F2.D.ln_sales_tax + F1.D.ln_sales_tax ]
all_pi[, lead.poly2 := 64*F8.D.ln_sales_tax + 49*F7.D.ln_sales_tax + 36*F6.D.ln_sales_tax + 25*F5.D.ln_sales_tax + 16*F4.D.ln_sales_tax + 9*F3.D.ln_sales_tax + 4*F2.D.ln_sales_tax + F1.D.ln_sales_tax ]
all_pi[, lead.poly3 := 512*F8.D.ln_sales_tax + 343*F7.D.ln_sales_tax + 216*F6.D.ln_sales_tax + 125*F5.D.ln_sales_tax + 64*F4.D.ln_sales_tax + 27*F3.D.ln_sales_tax + 8*F2.D.ln_sales_tax + F1.D.ln_sales_tax ]

all_pi[, lag.poly0 := D.ln_sales_tax + L8.D.ln_sales_tax + L7.D.ln_sales_tax + L6.D.ln_sales_tax + L5.D.ln_sales_tax + L4.D.ln_sales_tax + L3.D.ln_sales_tax + L2.D.ln_sales_tax + L1.D.ln_sales_tax ]
all_pi[, lag.poly1 := D.ln_sales_tax + 8*L8.D.ln_sales_tax + 7*L7.D.ln_sales_tax + 6*L6.D.ln_sales_tax + 5*L5.D.ln_sales_tax + 4*L4.D.ln_sales_tax + 3*L3.D.ln_sales_tax + 2*L2.D.ln_sales_tax + L1.D.ln_sales_tax ]
all_pi[, lag.poly2 := D.ln_sales_tax + 64*L8.D.ln_sales_tax + 49*L7.D.ln_sales_tax + 36*L6.D.ln_sales_tax + 25*L5.D.ln_sales_tax + 16*L4.D.ln_sales_tax + 9*L3.D.ln_sales_tax + 4*L2.D.ln_sales_tax + L1.D.ln_sales_tax ]
all_pi[, lag.poly3 := D.ln_sales_tax + 512*L8.D.ln_sales_tax + 343*L7.D.ln_sales_tax + 216*L6.D.ln_sales_tax + 125*L5.D.ln_sales_tax + 64*L4.D.ln_sales_tax + 27*L3.D.ln_sales_tax + 8*L2.D.ln_sales_tax + L1.D.ln_sales_tax ]
all_pi[, lag.poly4 := D.ln_sales_tax + 4096*L8.D.ln_sales_tax + 2401*L7.D.ln_sales_tax + 1296*L6.D.ln_sales_tax + 625*L5.D.ln_sales_tax + 256*L4.D.ln_sales_tax + 81*L3.D.ln_sales_tax + 16*L2.D.ln_sales_tax + L1.D.ln_sales_tax ]



### Estimation ---------------------------------------------------
all_pi <- all_pi[between(year, 2008, 2014)]
all_pi <- all_pi[ year >= 2009 | (year == 2008 & quarter >= 2)] ## First quarter of 2008, the difference was imputed not real data - so we drop it


formula_lead2 <- "lead.poly0 + lead.poly1 + lead.poly2"
formula_lead3 <- "lead.poly0 + lead.poly1 + lead.poly2 + lead.poly3"
formula_lag3 <- "lag.poly0 + lag.poly1 + lag.poly2 + lag.poly3"
formula_lag4 <- "lag.poly0 + lag.poly1 + lag.poly2 + lag.poly3 + lag.poly4"


outcomes <- c("D.ln_cpricei", "D.ln_quantity")
FE_opts <- c("cal_time", "module_by_time", "region_by_module_by_time", "division_by_module_by_time")
Econ_opts <- c("D.ln_unemp", "D.ln_home_price", "D.ln_unemp + D.ln_home_price")


## Create a matrix with controls for econ conditions that include leads and lags - also store indicators that will be used in final matrix with results
Econ_w_lags <- c("D.ln_unemp", "D.ln_unemp", "D.ln_unemp + D.ln_home_price", "D.ln_unemp + D.ln_home_price")
Econ_w_lags <- rbind(Econ_w_lags, c("Yes", "Yes", "Yes", "Yes"))
Econ_w_lags <- rbind(Econ_w_lags, c("No", "Yes", "No", "Yes"))
Econ_w_lags <- rbind(Econ_w_lags, c("L1.D2.ln_unemp + D.ln_unemp", "F8.D2.ln_unemp + D.ln_unemp + L1.D2.ln_unemp", "L1.D2.ln_unemp + D.ln_unemp L1.D2.ln_home_price + D.ln_home_price", "F8.D2.ln_unemp + D.ln_unemp + L1.D2.ln_unemp + F8.D2.ln_home_price + D.ln_home_price + L1.D2.ln_home_price"))


## Create a matrix with number of polynomials used for leads and lags
Poly_lags <- c(formula_lead2, formula_lead3, formula_lead3)
Poly_lags <- rbind(Poly_lags, c(formula_lag3, formula_lag3, formula_lag4))
Poly_lags <- rbind(Poly_lags, c(2, 3, 3))
Poly_lags <- rbind(Poly_lags, c(3, 3, 4))


LRdiff_res <- data.table(NULL)
for (Y in outcomes) {
  for (FE in FE_opts) {
    for(i in 1:dim(Poly_lags)[2]) {

      formula_RHS <- paste(Poly_lags[1,i], " + ", Poly_lags[2,i])

      formula1 <- as.formula(paste0(
        Y, "~", formula_RHS, "| ", FE, " | 0 | module_by_state"
      ))
      flog.info("Estimating with %s as outcome with %s FE.", Y, FE)
      res1 <- felm(formula = formula1, data = all_pi,
                   weights = all_pi$base.sales)
      flog.info("Finished estimating with %s as outcome with %s FE.", Y, FE)

      ## attach results
      flog.info("Writing results...")
      res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
      res1.dt[, outcome := Y]
      res1.dt[, controls := FE]
      res1.dt[, econ := "none"]
      res1.dt[, lag.econ := NA]
      res1.dt[, lead.econ := NA]
      res1.dt[, lead.poly := Poly_lags[3,i]]
      res1.dt[, lag.poly := Poly_lags[4,i]]
      res1.dt[, Rsq := summary(res1)$r.squared]
      res1.dt[, adj.Rsq := summary(res1)$adj.r.squared]
      LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
      fwrite(LRdiff_res, output.results.file)


      n.poly.lead <- Poly_lags[3,i]
      n.poly.lag <- Poly_lags[4,i]

      for(j in 1:8) { ## Number of leads and lags over which effect is assumed to matter

        ###### LEADS
        ## Create a name for estimate, se and pval of each lead
        lead.test.est.name <- paste("lead", j, ".test.est", sep = "")
        lead.test.se.name <- paste("lead", j, ".test.se", sep = "")
        lead.test.pval.name <- paste("lead", j, ".test.pval", sep = "")

        ## Create the formula to compute estimate at each lead
        lead.test.form <- "lead.poly0"
        for(k in 1:n.poly.lead) {

          lead.test.form <- paste(lead.test.form, " + lead.poly", k, "*", j^k, sep = "")

        }
        lead.test.form <- paste(lead.test.form, " = 0")


        ## Compute estimate and store in variables names
        lead.test <- glht(res1, linfct = lead.test.form)

        assign(lead.test.est.name, coef(summary(lead.test))[[1]])
        assign(lead.test.se.name, sqrt(vcov(summary(lead.test)))[[1]])
        assign(lead.test.pval.name, 2*(1 - pnorm(abs(coef(summary(lead.test))[[1]]/sqrt(vcov(summary(lead.test)))[[1]]))))


        ###### LAGS
        ## Create a name for estimate, se and pval of each lead
        lag.test.est.name <- paste("lag", j, ".test.est", sep = "")
        lag.test.se.name <- paste("lag", j, ".test.se", sep = "")
        lag.test.pval.name <- paste("lag", j, ".test.pval", sep = "")

        ## Create the formula to compute estimate at each lead
        lag.test.form <- "lag.poly0"
        for(k in 1:n.poly.lag) {

          lag.test.form <- paste(lag.test.form, " + lag.poly", k, "*", j^k, sep = "")

        }
        lag.test.form <- paste(lag.test.form, " = 0")


        ## Compute estimate and store in variables names
        lag.test <- glht(res1, linfct = lag.test.form)

        assign(lag.test.est.name, coef(summary(lag.test))[[1]])
        assign(lag.test.se.name, sqrt(vcov(summary(lag.test)))[[1]])
        assign(lag.test.pval.name, 2*(1 - pnorm(abs(coef(summary(lag.test))[[1]]/sqrt(vcov(summary(lag.test)))[[1]]))))

      }

      ## On Impact --> Effect = coefficient on lag.poly0
      lag0.test.est <- coef(summary(res1))[ "lag.poly0", "Estimate"]
      lag0.test.se <- coef(summary(res1))[ "lag.poly0", "Cluster s.e."]
      lag0.test.pval <- coef(summary(res1))[ "lag.poly0", "Pr(>|t|)"]

      ## sum leads
      flog.info("Summing leads...")
      lead.test.form <- "8*lead.poly0"
      for(k in 1:n.poly.lead) {

        tot.lead.n <- 1^k + 2^k + 3^k + 4^k + 5^k + 6^k + 7^k + 8^k
        lead.test.form <- paste(lead.test.form, " + ", tot.lead.n, "*lead.poly", k, sep = "")
      }
      lead.test.form <- paste(lead.test.form, " = 0", sep = "")

      lead.test <- glht(res1, linfct = lead.test.form)
      lead.test.est <- coef(summary(lead.test))[[1]]
      lead.test.se <- sqrt(vcov(summary(lead.test)))[[1]]
      lead.test.pval <- 2*(1 - pnorm(abs(lead.test.est/lead.test.se)))


      ## sum lags
      flog.info("Summing lags...")
      lag.test.form <- "9*lag.poly0"
      for(k in 1:n.poly.lag) {

        tot.lag.n <- 1^k + 2^k + 3^k + 4^k + 5^k + 6^k + 7^k + 8^k
        lag.test.form <- paste(lag.test.form, " + ", tot.lag.n, "*lag.poly", k, sep = "")
      }
      lag.test.form <- paste(lag.test.form, " = 0", sep = "")
      lag.test <- glht(res1, linfct = lag.test.form)
      lag.test.est <- coef(summary(lag.test))[[1]]
      lag.test.se <- sqrt(vcov(summary(lag.test)))[[1]]
      lag.test.pval <- 2*(1 - pnorm(abs(lag.test.est/lag.test.se)))


      ## linear hypothesis results
      lp.dt <- data.table(
        rn = c("lead8.D.ln_sales_tax", "lead7.D.ln_sales_tax", "lead6.D.ln_sales_tax", "lead5.D.ln_sales_tax", "lead4.D.ln_sales_tax", "lead3.D.ln_sales_tax", "lead2.D.ln_sales_tax", "lead1.D.ln_sales_tax", "Pre.D.ln_sales_tax", "lag0.D.ln_sales_tax", "lag1.D.ln_sales_tax", "lag2.D.ln_sales_tax", "lag3.D.ln_sales_tax", "lag4.D.ln_sales_tax", "lag5.D.ln_sales_tax", "lag6.D.ln_sales_tax", "lag7.D.ln_sales_tax", "lag8.D.ln_sales_tax", "Post.D.ln_sales_tax"),
        Estimate = c(lead8.test.est, lead7.test.est, lead6.test.est, lead5.test.est, lead4.test.est, lead3.test.est, lead2.test.est, lead1.test.est, lead.test.est, lag0.test.est, lag1.test.est, lag2.test.est, lag3.test.est, lag4.test.est, lag5.test.est, lag6.test.est, lag7.test.est, lag8.test.est, lag.test.est),
        `Cluster s.e.` = c(lead8.test.se, lead7.test.se, lead6.test.se, lead5.test.se, lead4.test.se, lead3.test.se, lead2.test.se, lead1.test.se, lead.test.se, lag0.test.se, lag1.test.se, lag2.test.se, lag3.test.se, lag4.test.se, lag5.test.se, lag6.test.se, lag7.test.se, lag8.test.se, lag.test.se),
        `Pr(>|t|)` = c(lead8.test.pval, lead7.test.pval, lead6.test.pval, lead5.test.pval, lead4.test.pval, lead3.test.pval, lead2.test.pval, lead1.test.pval, lead.test.pval, lag0.test.pval, lag1.test.pval, lag2.test.pval, lag3.test.pval, lag4.test.pval, lag5.test.pval, lag6.test.pval, lag7.test.pval, lag8.test.pval, lag.test.pval),
        outcome = Y,
        controls = FE,
        econ = "none",
        lag.econ = NA,
        lead.econ = NA,
        lead.poly = Poly_lags[3,i],
        lag.poly = Poly_lags[4,i],
        Rsq = summary(res1)$r.squared,
        adj.Rsq = summary(res1)$adj.r.squared)
      LRdiff_res <- rbind(LRdiff_res, lp.dt, fill = T)
      fwrite(LRdiff_res, output.results.file)


      ##
      for(EC in Econ_opts) {


        #formula_RHS <- paste(Poly_lags[1,i], " + ", Poly_lags[2,i])

        formula1 <- as.formula(paste0(
          Y, "~", formula_RHS, " + ", EC, "| ", FE, " | 0 | module_by_state"
        ))
        flog.info("Estimating with %s as outcome with %s FE.", Y, FE)
        res1 <- felm(formula = formula1, data = all_pi,
                     weights = all_pi$base.sales)
        flog.info("Finished estimating with %s as outcome with %s FE.", Y, FE)


        ## attach results
        flog.info("Writing results...")
        res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
        res1.dt[, outcome := Y]
        res1.dt[, controls := FE]
        res1.dt[, econ := EC]
        res1.dt[, lag.econ := "No"]
        res1.dt[, lead.econ := "No"]
        res1.dt[, lead.poly := Poly_lags[3,i]]
        res1.dt[, lag.poly := Poly_lags[4,i]]
        res1.dt[, Rsq := summary(res1)$r.squared]
        res1.dt[, adj.Rsq := summary(res1)$adj.r.squared]
        LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
        fwrite(LRdiff_res, output.results.file)


        n.poly.lead <- Poly_lags[3,i]
        n.poly.lag <- Poly_lags[4,i]

        for(j in 1:8) { ## Number of leads and lags over which effect is assumed to matter

          ###### LEADS
          ## Create a name for estimate, se and pval of each lead
          lead.test.est.name <- paste("lead", j, ".test.est", sep = "")
          lead.test.se.name <- paste("lead", j, ".test.se", sep = "")
          lead.test.pval.name <- paste("lead", j, ".test.pval", sep = "")

          ## Create the formula to compute estimate at each lead
          lead.test.form <- "lead.poly0"
          for(k in 1:n.poly.lead) {

            lead.test.form <- paste(lead.test.form, " + lead.poly", k, "*", j^k, sep = "")

          }
          lead.test.form <- paste(lead.test.form, " = 0", sep = "")


          ## Compute estimate and store in variables names
          lead.test <- glht(res1, linfct = lead.test.form)

          assign(lead.test.est.name, coef(summary(lead.test))[[1]])
          assign(lead.test.se.name, sqrt(vcov(summary(lead.test)))[[1]])
          assign(lead.test.pval.name, 2*(1 - pnorm(abs(coef(summary(lead.test))[[1]]/sqrt(vcov(summary(lead.test)))[[1]]))))


          ###### LAGS
          ## Create a name for estimate, se and pval of each lead
          lag.test.est.name <- paste("lag", j, ".test.est", sep = "")
          lag.test.se.name <- paste("lag", j, ".test.se", sep = "")
          lag.test.pval.name <- paste("lag", j, ".test.pval", sep = "")

          ## Create the formula to compute estimate at each lead
          lag.test.form <- "lag.poly0"
          for(k in 1:n.poly.lag) {

            lag.test.form <- paste(lag.test.form, " + lag.poly", k, "*", j^k, sep = "")

          }
          lag.test.form <- paste(lag.test.form, " = 0", sep = "")


          ## Compute estimate and store in variables names
          lag.test <- glht(res1, linfct = lag.test.form)

          assign(lag.test.est.name, coef(summary(lag.test))[[1]])
          assign(lag.test.se.name, sqrt(vcov(summary(lag.test)))[[1]])
          assign(lag.test.pval.name, 2*(1 - pnorm(abs(coef(summary(lag.test))[[1]]/sqrt(vcov(summary(lag.test)))[[1]]))))

        }

        ## On Impact --> Effect = coefficient on lag.poly0
        lag0.test.est <- coef(summary(res1))[ "lag.poly0", "Estimate"]
        lag0.test.se <- coef(summary(res1))[ "lag.poly0", "Cluster s.e."]
        lag0.test.pval <- coef(summary(res1))[ "lag.poly0", "Pr(>|t|)"]

        ## sum leads
        flog.info("Summing leads...")
        lead.test.form <- "8*lead.poly0"
        for(k in 1:n.poly.lead) {

          tot.lead.n <- 1^k + 2^k + 3^k + 4^k + 5^k + 6^k + 7^k + 8^k
          lead.test.form <- paste(lead.test.form, " + ", tot.lead.n, "*lead.poly", k, sep = "")
        }
        lead.test.form <- paste(lead.test.form, " = 0", sep = "")

        lead.test <- glht(res1, linfct = lead.test.form)
        lead.test.est <- coef(summary(lead.test))[[1]]
        lead.test.se <- sqrt(vcov(summary(lead.test)))[[1]]
        lead.test.pval <- 2*(1 - pnorm(abs(lead.test.est/lead.test.se)))


        ## sum lags
        flog.info("Summing lags...")
        lag.test.form <- "9*lag.poly0"
        for(k in 1:n.poly.lag) {

          tot.lag.n <- 1^k + 2^k + 3^k + 4^k + 5^k + 6^k + 7^k + 8^k
          lag.test.form <- paste(lag.test.form, " + ", tot.lag.n, "*lag.poly", k, sep = "")
        }
        lag.test.form <- paste(lag.test.form, " = 0", sep = "")
        lag.test <- glht(res1, linfct = lag.test.form)
        lag.test.est <- coef(summary(lag.test))[[1]]
        lag.test.se <- sqrt(vcov(summary(lag.test)))[[1]]
        lag.test.pval <- 2*(1 - pnorm(abs(lag.test.est/lag.test.se)))


        ## linear hypothesis results
        lp.dt <- data.table(
          rn = c("lead8.D.ln_sales_tax", "lead7.D.ln_sales_tax", "lead6.D.ln_sales_tax", "lead5.D.ln_sales_tax", "lead4.D.ln_sales_tax", "lead3.D.ln_sales_tax", "lead2.D.ln_sales_tax", "lead1.D.ln_sales_tax", "Pre.D.ln_sales_tax", "lag0.D.ln_sales_tax", "lag1.D.ln_sales_tax", "lag2.D.ln_sales_tax", "lag3.D.ln_sales_tax", "lag4.D.ln_sales_tax", "lag5.D.ln_sales_tax", "lag6.D.ln_sales_tax", "lag7.D.ln_sales_tax", "lag8.D.ln_sales_tax", "Post.D.ln_sales_tax"),
          Estimate = c(lead8.test.est, lead7.test.est, lead6.test.est, lead5.test.est, lead4.test.est, lead3.test.est, lead2.test.est, lead1.test.est, lead.test.est, lag0.test.est, lag1.test.est, lag2.test.est, lag3.test.est, lag4.test.est, lag5.test.est, lag6.test.est, lag7.test.est, lag8.test.est, lag.test.est),
          `Cluster s.e.` = c(lead8.test.se, lead7.test.se, lead6.test.se, lead5.test.se, lead4.test.se, lead3.test.se, lead2.test.se, lead1.test.se, lead.test.se, lag0.test.se, lag1.test.se, lag2.test.se, lag3.test.se, lag4.test.se, lag5.test.se, lag6.test.se, lag7.test.se, lag8.test.se, lag.test.se),
          `Pr(>|t|)` = c(lead8.test.pval, lead7.test.pval, lead6.test.pval, lead5.test.pval, lead4.test.pval, lead3.test.pval, lead2.test.pval, lead1.test.pval, lead.test.pval, lag0.test.pval, lag1.test.pval, lag2.test.pval, lag3.test.pval, lag4.test.pval, lag5.test.pval, lag6.test.pval, lag7.test.pval, lag8.test.pval, lag.test.pval),
          outcome = Y,
          controls = FE,
          econ = EC,
          lag.econ = "No",
          lead.econ = "No",
          lead.poly = Poly_lags[3,i],
          lag.poly = Poly_lags[4,i],
          Rsq = summary(res1)$r.squared,
          adj.Rsq = summary(res1)$adj.r.squared)
        LRdiff_res <- rbind(LRdiff_res, lp.dt, fill = T)
        fwrite(LRdiff_res, output.results.file)

      }


      ##
      for(i in 1:dim(Econ_w_lags)[2]) {

        #formula_RHS <- paste(Poly_lags[1,i], " + ", Poly_lags[2,i])
        EC <- Econ_w_lags[4, i]

        formula1 <- as.formula(paste0(
          Y, "~", formula_RHS, " + ", EC, "| ", FE, " | 0 | module_by_state"
        ))
        flog.info("Estimating with %s as outcome with %s FE.", Y, FE)
        res1 <- felm(formula = formula1, data = all_pi,
                     weights = all_pi$base.sales)
        flog.info("Finished estimating with %s as outcome with %s FE.", Y, FE)


        ## attach results
        flog.info("Writing results...")
        res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
        res1.dt[, outcome := Y]
        res1.dt[, controls := FE]
        res1.dt[, econ := Econ_w_lags[1, i]]
        res1.dt[, lag.econ := Econ_w_lags[2, i]]
        res1.dt[, lead.econ := Econ_w_lags[3,i]]
        res1.dt[, lead.poly := Poly_lags[3,i]]
        res1.dt[, lag.poly := Poly_lags[4,i]]
        res1.dt[, Rsq := summary(res1)$r.squared]
        res1.dt[, adj.Rsq := summary(res1)$adj.r.squared]
        LRdiff_res <- rbind(LRdiff_res, res1.dt, fill = T)
        fwrite(LRdiff_res, output.results.file)


        n.poly.lead <- Poly_lags[3,i]
        n.poly.lag <- Poly_lags[4,i]

        for(j in 1:8) { ## Number of leads and lags over which effect is assumed to matter

          ###### LEADS
          ## Create a name for estimate, se and pval of each lead
          lead.test.est.name <- paste("lead", j, ".test.est", sep = "")
          lead.test.se.name <- paste("lead", j, ".test.se", sep = "")
          lead.test.pval.name <- paste("lead", j, ".test.pval", sep = "")

          ## Create the formula to compute estimate at each lead
          lead.test.form <- "lead.poly0"
          for(k in 1:n.poly.lead) {

            lead.test.form <- paste(lead.test.form, " + lead.poly", k, "*", j^k, sep = "")

          }
          lead.test.form <- paste(lead.test.form, " = 0", sep = "")


          ## Compute estimate and store in variables names
          lead.test <- glht(res1, linfct = lead.test.form)

          assign(lead.test.est.name, coef(summary(lead.test))[[1]])
          assign(lead.test.se.name, sqrt(vcov(summary(lead.test)))[[1]])
          assign(lead.test.pval.name, 2*(1 - pnorm(abs(coef(summary(lead.test))[[1]]/sqrt(vcov(summary(lead.test)))[[1]]))))


          ###### LAGS
          ## Create a name for estimate, se and pval of each lead
          lag.test.est.name <- paste("lag", j, ".test.est", sep = "")
          lag.test.se.name <- paste("lag", j, ".test.se", sep = "")
          lag.test.pval.name <- paste("lag", j, ".test.pval", sep = "")

          ## Create the formula to compute estimate at each lead
          lag.test.form <- "lag.poly0"
          for(k in 1:n.poly.lag) {

            lag.test.form <- paste(lag.test.form, " + lag.poly", k, "*", j^k, sep = "")

          }
          lag.test.form <- paste(lag.test.form, " = 0", sep = "")


          ## Compute estimate and store in variables names
          lag.test <- glht(res1, linfct = lag.test.form)

          assign(lag.test.est.name, coef(summary(lag.test))[[1]])
          assign(lag.test.se.name, sqrt(vcov(summary(lag.test)))[[1]])
          assign(lag.test.pval.name, 2*(1 - pnorm(abs(coef(summary(lag.test))[[1]]/sqrt(vcov(summary(lag.test)))[[1]]))))

        }

        ## On Impact --> Effect = coefficient on lag.poly0
        lag0.test.est <- coef(summary(res1))[ "lag.poly0", "Estimate"]
        lag0.test.se <- coef(summary(res1))[ "lag.poly0", "Cluster s.e."]
        lag0.test.pval <- coef(summary(res1))[ "lag.poly0", "Pr(>|t|)"]

        ## sum leads
        flog.info("Summing leads...")
        lead.test.form <- "8*lead.poly0"
        for(k in 1:n.poly.lead) {

          tot.lead.n <- 1^k + 2^k + 3^k + 4^k + 5^k + 6^k + 7^k + 8^k
          lead.test.form <- paste(lead.test.form, " + ", tot.lead.n, "*lead.poly", k, sep = "")
        }
        lead.test.form <- paste(lead.test.form, " = 0", sep = "")

        lead.test <- glht(res1, linfct = lead.test.form)
        lead.test.est <- coef(summary(lead.test))[[1]]
        lead.test.se <- sqrt(vcov(summary(lead.test)))[[1]]
        lead.test.pval <- 2*(1 - pnorm(abs(lead.test.est/lead.test.se)))


        ## sum lags
        flog.info("Summing lags...")
        lag.test.form <- "9*lag.poly0"
        for(k in 1:n.poly.lag) {

          tot.lag.n <- 1^k + 2^k + 3^k + 4^k + 5^k + 6^k + 7^k + 8^k
          lag.test.form <- paste(lag.test.form, " + ", tot.lag.n, "*lag.poly", k, sep = "")
        }
        lag.test.form <- paste(lag.test.form, " = 0", sep = "")
        lag.test <- glht(res1, linfct = lag.test.form)
        lag.test.est <- coef(summary(lag.test))[[1]]
        lag.test.se <- sqrt(vcov(summary(lag.test)))[[1]]
        lag.test.pval <- 2*(1 - pnorm(abs(lag.test.est/lag.test.se)))


        ## linear hypothesis results
        lp.dt <- data.table(
          rn = c("lead8.D.ln_sales_tax", "lead7.D.ln_sales_tax", "lead6.D.ln_sales_tax", "lead5.D.ln_sales_tax", "lead4.D.ln_sales_tax", "lead3.D.ln_sales_tax", "lead2.D.ln_sales_tax", "lead1.D.ln_sales_tax", "Pre.D.ln_sales_tax", "lag0.D.ln_sales_tax", "lag1.D.ln_sales_tax", "lag2.D.ln_sales_tax", "lag3.D.ln_sales_tax", "lag4.D.ln_sales_tax", "lag5.D.ln_sales_tax", "lag6.D.ln_sales_tax", "lag7.D.ln_sales_tax", "lag8.D.ln_sales_tax", "Post.D.ln_sales_tax"),
          Estimate = c(lead8.test.est, lead7.test.est, lead6.test.est, lead5.test.est, lead4.test.est, lead3.test.est, lead2.test.est, lead1.test.est, lead.test.est, lag0.test.est, lag1.test.est, lag2.test.est, lag3.test.est, lag4.test.est, lag5.test.est, lag6.test.est, lag7.test.est, lag8.test.est, lag.test.est),
          `Cluster s.e.` = c(lead8.test.se, lead7.test.se, lead6.test.se, lead5.test.se, lead4.test.se, lead3.test.se, lead2.test.se, lead1.test.se, lead.test.se, lag0.test.se, lag1.test.se, lag2.test.se, lag3.test.se, lag4.test.se, lag5.test.se, lag6.test.se, lag7.test.se, lag8.test.se, lag.test.se),
          `Pr(>|t|)` = c(lead8.test.pval, lead7.test.pval, lead6.test.pval, lead5.test.pval, lead4.test.pval, lead3.test.pval, lead2.test.pval, lead1.test.pval, lead.test.pval, lag0.test.pval, lag1.test.pval, lag2.test.pval, lag3.test.pval, lag4.test.pval, lag5.test.pval, lag6.test.pval, lag7.test.pval, lag8.test.pval, lag.test.pval),
          outcome = Y,
          controls = FE,
          econ = Econ_w_lags[1, i],
          lag.econ = Econ_w_lags[2, i],
          lead.econ = Econ_w_lags[3,i],
          lead.poly = Poly_lags[3,i],
          lag.poly = Poly_lags[4,i],
          Rsq = summary(res1)$r.squared,
          adj.Rsq = summary(res1)$adj.r.squared)
        LRdiff_res <- rbind(LRdiff_res, lp.dt, fill = T)
        fwrite(LRdiff_res, output.results.file)


      }
    }
  }
}

## summary values --------------------------------------------------------------
LRdiff_res$N_obs <- nrow(all_pi)
LRdiff_res$N_modules <- length(unique(all_pi$product_module_code))
LRdiff_res$N_stores <- length(unique(all_pi$store_code_uc))
LRdiff_res$N_counties <- uniqueN(all_pi, by = c("fips_state", "fips_county"))
LRdiff_res$N_years <- uniqueN(all_pi, by = c("year")) # should be 6 (we lose one because we difference)
LRdiff_res$N_county_modules <- uniqueN(all_pi, by = c("fips_state", "fips_county",
                                                           "product_module_code"))

fwrite(LRdiff_res, output.results.file)


