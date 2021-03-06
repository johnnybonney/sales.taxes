#' Authors: John Bonney and Lancelot Henry de Frahan


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
data.full.path <- "Data/Nielsen/semester_nielsen_data.csv"
## output filepaths ----------------------------------------------
reg.outfile <- "Data/LRdiff_results_semester_diff_leadlags_cohortbycohort.csv"


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

## prep the 2006-2016 data ---------------------------------------
all_pi <- fread(data.full.path)
#old_pi <- fread(old_pi_path)

## merge on the old price indices
#all_pi <- merge(all_pi, old_pi,
#                     by = c("fips_state", "fips_county", "store_code_uc",
#                            "product_module_code", "year", "quarter"), all = T)
#rm(old_pi)

## merge on the census region/division info
all_pi <- merge(all_pi, geo_dt, by = "fips_state")


# create necessary variables
all_pi[, store_by_module := .GRP, by = .(store_code_uc, product_module_code)]
all_pi[, cal_time := 2 * year + semester]
all_pi[, module_by_time := .GRP, by = .(product_module_code, cal_time)]
all_pi[, module_by_state := .GRP, by = .(product_module_code, fips_state)]
all_pi[, region_by_module_by_time := .GRP, by = .(region, product_module_code, cal_time)]
all_pi[, division_by_module_by_time := .GRP, by = .(division, product_module_code, cal_time)]

## Balance the sample
all_pi <- all_pi[!is.na(base.sales) & !is.na(sales) & !is.na(ln_cpricei) &
                             !is.na(ln_sales_tax) & !is.na(ln_quantity) &
                             !is.na(ln_sales_tax_Q2) & !is.na(ln_cpricei_Q2) & !is.na(ln_quantity_Q2)]

## balance on store-module level
keep_store_modules <- all_pi[, list(n = .N),
                                  by = .(store_code_uc, product_module_code)]
keep_store_modules <- keep_store_modules[n == (2016 - 2005) * 2]

setkey(all_pi, store_code_uc, product_module_code)
setkey(keep_store_modules, store_code_uc, product_module_code)

all_pi <- all_pi[keep_store_modules]
setkey(all_pi, store_code_uc, product_module_code, year, semester)

## take first differences of outcomes and treatment
all_pi[, D.ln_cpricei := ln_cpricei - shift(ln_cpricei, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_cpricei_Q2 := ln_cpricei_Q2 - shift(ln_cpricei_Q2, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_quantity := ln_quantity - shift(ln_quantity, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_quantity_Q2 := ln_quantity_Q2 - shift(ln_quantity_Q2, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_sales_tax := ln_sales_tax - shift(ln_sales_tax, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]

all_pi[, D.ln_sales_tax_Q2 := ln_sales_tax_Q2 - shift(ln_sales_tax_Q2, n=1, type="lag"),
       by = .(store_code_uc, product_module_code)]


## generate lags and leads of ln_sales_tax
for (lag.val in 1:4) {
  lag.X <- paste0("L", lag.val, ".D.ln_sales_tax")
  all_pi[, (lag.X) := shift(D.ln_sales_tax, n=lag.val, type="lag"),
         by = .(store_code_uc, product_module_code)]

  lead.X <- paste0("F", lag.val, ".D.ln_sales_tax")
  all_pi[, (lead.X) := shift(D.ln_sales_tax, n=lag.val, type="lead"),
         by = .(store_code_uc, product_module_code)]

  lag.X <- paste0("L", lag.val, ".D.ln_sales_tax_Q2")
  all_pi[, (lag.X) := shift(D.ln_sales_tax_Q2, n=lag.val, type="lag"),
         by = .(store_code_uc, product_module_code)]

  lead.X <- paste0("F", lag.val, ".D.ln_sales_tax_Q2")
  all_pi[, (lead.X) := shift(D.ln_sales_tax_Q2, n=lag.val, type="lead"),
         by = .(store_code_uc, product_module_code)]
}


### Estimation ---------------------------------------------------
all_pi <- all_pi[between(year, 2008, 2014)]
all_pi <- all_pi[ year >= 2009 | (year == 2008 & semester == 2)] ## First semester of 2008, the difference was imputed not real data - so we drop it

formula_lags <- paste0("L", 1:4, ".D.ln_sales_tax", collapse = "+")
formula_leads <- paste0("F", 1:4, ".D.ln_sales_tax", collapse = "+")
formula_RHS <- paste0("D.ln_sales_tax + ", formula_lags, "+", formula_leads)

formula_lags_Q2 <- paste0("L", 1:4, ".D.ln_sales_tax_Q2", collapse = "+")
formula_leads_Q2 <- paste0("F", 1:4, ".D.ln_sales_tax_Q2", collapse = "+")
formula_RHS_Q2 <- paste0("D.ln_sales_tax_Q2 + ", formula_lags_Q2, "+", formula_leads_Q2)

outcomes <- c("D.ln_cpricei", "D.ln_quantity")
outcomes.Q2 <- c("D.ln_cpricei_Q2", "D.ln_quantity_Q2")
FE_opts <- c("cal_time", "module_by_time", "region_by_module_by_time", "division_by_module_by_time")

## for linear hypothesis tests
lead.vars <- paste(paste0("F", 4:1, ".D.ln_sales_tax"), collapse = " + ")
lag.vars <- paste(paste0("L", 4:1, ".D.ln_sales_tax"), collapse = " + ")
lead.vars.Q2 <- paste(paste0("F", 4:1, ".D.ln_sales_tax_Q2"), collapse = " + ")
lag.vars.Q2 <- paste(paste0("L", 4:1, ".D.ln_sales_tax_Q2"), collapse = " + ")
lead.lp.restr <- paste(lead.vars, "= 0")
lead.lp.restr.Q2 <- paste(lead.vars.Q2, "= 0")
lag.lp.restr <- paste(lag.vars, "+ D.ln_sales_tax = 0")
lag.lp.restr.Q2 <- paste(lag.vars.Q2, "+ D.ln_sales_tax_Q2 = 0")
total.lp.restr <- paste(lag.vars, "+", lead.vars, "+ D.ln_sales_tax = 0")
total.lp.restr.Q2 <- paste(lag.vars.Q2, "+", lead.vars.Q2, "+ D.ln_sales_tax_Q2 = 0")


##
print(" Start with mean ln_sales_tax in each semester")
##

res.table <- data.table(NULL)
for (Y in outcomes) {
  for (FE in FE_opts) {
    formula1 <- as.formula(paste0(
      Y, "~", formula_RHS, "| ", FE, " | 0 | module_by_state"
    ))
    flog.info("Estimating with %s as outcome with %s FE.", Y, FE)
    res1 <- felm(formula = formula1, data = all_pi,
                 weights = all_pi$base.sales)
    flog.info("Finished estimating with %s as outcome with %s FE.", Y, FE)

    ## sum leads
    flog.info("Summing leads...")
    lead.test <- glht(res1, linfct = lead.lp.restr)
    lead.test.est <- coef(summary(lead.test))[[1]]
    lead.test.se <- sqrt(vcov(summary(lead.test)))[[1]]
    lead.test.pval <- 2*(1 - pnorm(abs(lead.test.est/lead.test.se)))

    ## sum lags
    flog.info("Summing lags...")
    lag.test <- glht(res1, linfct = lag.lp.restr)
    lag.test.est <- coef(summary(lag.test))[[1]]
    lag.test.se <- sqrt(vcov(summary(lag.test)))[[1]]
    lag.test.pval <- 2*(1 - pnorm(abs(lag.test.est/lag.test.se)))

    ## sum all
    flog.info("Summing all...")
    total.test <- glht(res1, linfct = total.lp.restr)
    total.test.est <- coef(summary(total.test))[[1]]
    total.test.se <- sqrt(vcov(summary(total.test)))[[1]]
    total.test.pval <- 2*(1 - pnorm(abs(total.test.est/total.test.se)))

    ## linear hypothesis results
    lp.dt <- data.table(
       rn = c("Pre.D.ln_sales_tax", "Post.D.ln_sales_tax", "All.D.ln_sales_tax"),
       Estimate = c(lead.test.est, lag.test.est, total.test.est),
       `Cluster s.e.` = c(lead.test.se, lag.test.se, total.test.se),
       `Pr(>|t|)` = c(lead.test.pval, lag.test.pval, total.test.pval),
       outcome = Y,
       controls = FE
    )

    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, controls := FE]
    res.table <- rbind(res.table, res1.dt, fill = T)
    res.table <- rbind(res.table, lp.dt, fill = T)
    fwrite(res.table, reg.outfile)
  }
}

##
print("Now use ln_sales_tax_Q2")
##
for (Y in c(outcomes, outcomes.Q2)) {
  for (FE in FE_opts) {
    formula1 <- as.formula(paste0(
      Y, "~", formula_RHS_Q2, "| ", FE, " | 0 | module_by_state"
    ))
    flog.info("Estimating with %s as outcome with %s FE.", Y, FE)
    res1 <- felm(formula = formula1, data = all_pi,
                 weights = all_pi$base.sales)
    flog.info("Finished estimating with %s as outcome with %s FE.", Y, FE)

    ## sum leads
    flog.info("Summing leads...")
    lead.test <- glht(res1, linfct = lead.lp.restr.Q2)
    lead.test.est <- coef(summary(lead.test))[[1]]
    lead.test.se <- sqrt(vcov(summary(lead.test)))[[1]]
    lead.test.pval <- 2*(1 - pnorm(abs(lead.test.est/lead.test.se)))

    ## sum lags
    flog.info("Summing lags...")
    lag.test <- glht(res1, linfct = lag.lp.restr.Q2)
    lag.test.est <- coef(summary(lag.test))[[1]]
    lag.test.se <- sqrt(vcov(summary(lag.test)))[[1]]
    lag.test.pval <- 2*(1 - pnorm(abs(lag.test.est/lag.test.se)))

    ## sum all
    flog.info("Summing all...")
    total.test <- glht(res1, linfct = total.lp.restr.Q2)
    total.test.est <- coef(summary(total.test))[[1]]
    total.test.se <- sqrt(vcov(summary(total.test)))[[1]]
    total.test.pval <- 2*(1 - pnorm(abs(total.test.est/total.test.se)))

    ## linear hypothesis results
    lp.dt <- data.table(
      rn = c("Pre.D.ln_sales_tax_Q2", "Post.D.ln_sales_tax_Q2", "All.D.ln_sales_tax_Q2"),
      Estimate = c(lead.test.est, lag.test.est, total.test.est),
      `Cluster s.e.` = c(lead.test.se, lag.test.se, total.test.se),
      `Pr(>|t|)` = c(lead.test.pval, lag.test.pval, total.test.pval),
      outcome = Y,
      controls = FE
    )

    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, controls := FE]
    res.table <- rbind(res.table, res1.dt, fill = T)
    res.table <- rbind(res.table, lp.dt, fill = T)
    fwrite(res.table, reg.outfile)
  }
}
