#' Author: John Bonney
#'
#' We want to run a specification in levels using semesterly data. The steps
#' are as follows:
#'    1) balance data from 2006-2016
#'    2) limit to 2008-2014 data (subset based on how many lags/leads you are going to use)
#'    3) demean the data on the store-module level
#'    4) For each semester 2009-2014,
#'       -regress Y on 2-4 leads of treatment and 0-4 lags (however many are possible)
#'       -do this in one regression (interacting with year "cohorts")
#'    5) for each lead and lag, average across cohorts (equally weighted)
#'    6) save the number of module-stores (also save output of the number of parameters
#'       that were estimated)

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
reg.outfile <- "Data/semesterly_pi_output_pooled.csv"

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

## Balance the sample from 2006-2016
all_pi <- all_pi[!is.na(base.sales) & !is.na(sales) & !is.na(ln_cpricei) &
                   !is.na(ln_sales_tax) & !is.na(ln_quantity)]

## balance on store-module level
keep_store_modules <- all_pi[, list(n = .N),
                             by = .(store_code_uc, product_module_code)]
keep_store_modules <- keep_store_modules[n == (2016 - 2005) * 2]

setkey(all_pi, store_code_uc, product_module_code)
setkey(keep_store_modules, store_code_uc, product_module_code)

all_pi <- all_pi[keep_store_modules]
setkey(all_pi, store_code_uc, product_module_code, year, semester)

## keep only 2008-2014
all_pi <- all_pi[between(year, 2008, 2014)]

## demean the outcomes/treatment on the store-module level
all_pi[, ln_cpricei := ln_cpricei - mean(ln_cpricei), by = .(store_code_uc, product_module_code)]
all_pi[, ln_quantity := ln_quantity - mean(ln_quantity), by = .(store_code_uc, product_module_code)]
all_pi[, ln_sales_tax := ln_sales_tax - mean(ln_sales_tax), by = .(store_code_uc, product_module_code)]

## generate leads and lags of treatment
for (lag.val in 1:4) {
  lag.X <- paste0("L", lag.val, ".ln_sales_tax")
  all_pi[, (lag.X) := shift(ln_sales_tax, n=lag.val, type="lag"),
         by = .(store_code_uc, product_module_code)]

  lead.X <- paste0("F", lag.val, ".ln_sales_tax")
  all_pi[, (lead.X) := shift(ln_sales_tax, n=lag.val, type="lead"),
         by = .(store_code_uc, product_module_code)]
}
all_pi <- all_pi[between(year, 2009, 2014)]

## generate interacted leads and lags (interacted with year-semester)
all_lags_leads <- c(
  paste0("F", c(1, 3, 4), ".ln_sales_tax"), # omitting t=-2
  "ln_sales_tax", paste0("L", 1:4, ".ln_sales_tax")
)
X_vec <- NULL
for (yr in 2009:2014) {
  for (smstr in 1:2) {
    yr_smstr <- paste0(yr, "S", smstr)
    for (LX in all_lags_leads) {
      if      (yr == 2009 & smstr == 1 & LX == "L3.ln_sales_tax") next
      else if (yr == 2009 & LX == "L4.ln_sales_tax") next
      else if (yr >= 2013 & LX == "F4.ln_sales_tax") next
      else if (yr == 2013 & smstr == 2 & LX == "F3.ln_sales_tax") next
      else if (yr == 2014 & LX  %in% c("F3.ln_sales_tax", "F2.ln_sales_tax")) next
      else if (yr == 2014 & smstr == 2 & LX == "F1.ln_sales_tax") next
      new_var <- paste0(LX, ".", yr_smstr)
      all_pi[, (new_var) := ifelse(year != yr | semester != smstr, 0, get(LX))]
      # NA should only happen if the year-semester is outside 2008-2014
      print(nrow(all_pi[is.na(get(new_var))]))
      X_vec <- c(X_vec, new_var)
    }
  }
}

### Estimation ---------------------------------------------------
formula_RHS <- paste0(X_vec, collapse = "+")

outcomes <- c("ln_cpricei", "ln_quantity")
FE_opts <- c("cal_time", "module_by_time",
             "region_by_module_by_time",
             "division_by_module_by_time")

## for linear hypothesis tests
## need to take the average for each lag/lead and then take the average of the
## averages...
F4.vars <- X_vec[grepl("F4", X_vec)]
F4.LC <- paste0("(", paste(F4.vars, collapse = "+"), ") / ", length(F4.vars), "=0")
F3.vars <- X_vec[grepl("F3", X_vec)]
F3.LC <- paste0("(", paste(F3.vars, collapse = "+"), ") / ", length(F3.vars), "=0")
F1.vars <- X_vec[grepl("F1", X_vec)]
F1.LC <- paste0("(", paste(F1.vars, collapse = "+"), ") / ", length(F1.vars), "=0")
L0.vars <- X_vec[grepl("^ln", X_vec)]
L0.LC <- paste0("(", paste(L0.vars, collapse = "+"), ") / ", length(L0.vars), "=0")
L1.vars <- X_vec[grepl("L1", X_vec)]
L1.LC <- paste0("(", paste(L1.vars, collapse = "+"), ") / ", length(L1.vars), "=0")
L2.vars <- X_vec[grepl("L2", X_vec)]
L2.LC <- paste0("(", paste(L2.vars, collapse = "+"), ") / ", length(L2.vars), "=0")
L3.vars <- X_vec[grepl("L3", X_vec)]
L3.LC <- paste0("(", paste(L3.vars, collapse = "+"), ") / ", length(L3.vars), "=0")
L4.vars <- X_vec[grepl("L4", X_vec)]
L4.LC <- paste0("(", paste(L4.vars, collapse = "+"), ") / ", length(L4.vars), "=0")

lead.vars <- paste(
  "(", paste(F4.vars, collapse = " + "), ") / ", length(F4.vars) * 3,
  " + (", paste(F3.vars, collapse = " + "), ") / ", length(F3.vars) * 3,
  " + (", paste(F1.vars, collapse = " + "), ") / ", length(F1.vars) * 3
)

lag.vars <- paste(
  "(", paste(L0.vars, collapse = " + "), ") / ", length(L0.vars) * 5,
  " + (", paste(L1.vars, collapse = " + "), ") / ", length(L1.vars) * 5,
  " + (", paste(L2.vars, collapse = " + "), ") / ", length(L2.vars) * 5,
  " + (", paste(L3.vars, collapse = " + "), ") / ", length(L3.vars) * 5,
  " + (", paste(L4.vars, collapse = " + "), ") / ", length(L4.vars) * 5
)

total.vars <- paste(
  "(", paste(F4.vars, collapse = " + "), ") / ", length(F4.vars) * 8,
  " + (", paste(F3.vars, collapse = " + "), ") / ", length(F3.vars) * 8,
  " + (", paste(F1.vars, collapse = " + "), ") / ", length(F1.vars) * 8,
  " + (", paste(L0.vars, collapse = " + "), ") / ", length(L0.vars) * 8,
  " + (", paste(L1.vars, collapse = " + "), ") / ", length(L1.vars) * 8,
  " + (", paste(L2.vars, collapse = " + "), ") / ", length(L2.vars) * 8,
  " + (", paste(L3.vars, collapse = " + "), ") / ", length(L3.vars) * 8,
  " + (", paste(L4.vars, collapse = " + "), ") / ", length(L4.vars) * 8
)

lead.lp.restr <- paste(lead.vars, "= 0")
lag.lp.restr <- paste(lag.vars, "= 0")
total.lp.restr <- paste(total.vars, "= 0")

## collect results
N_module_stores <- nrow(unique(all_pi[, .(store_code_uc, product_module_code)]))
res.table <- data.table(NULL)
for (Y in outcomes[2]) {
  for (FE in FE_opts[1:2]) {
    formula1 <- as.formula(paste0(
      Y, "~", formula_RHS, "| ", FE, " | 0 | module_by_state"
    ))
    flog.info("Estimating with %s as outcome with %s FE.", Y, FE)
    res1 <- felm(formula = formula1, data = all_pi,
                 weights = all_pi$base.sales)
    flog.info("Finished estimating with %s as outcome with %s FE.", Y, FE)

    ## sum for each lead/lag
    leadlag.dt <- data.table(NULL)
    for (LC in c("F4", "F3", "F1", "L0", "L1", "L2", "L3", "L4")) {
      flog.info("Summing %s...", LC)
      eval(parse(text = paste0(
        "temp.test <- glht(res1, ", LC, ".LC)"
      )))
      temp.test.est <- coef(summary(temp.test))[[1]]
      temp.test.se <- sqrt(vcov(summary(temp.test)))[[1]]
      temp.test.pval <- 2*(1 - pnorm(abs(temp.test.est/temp.test.se)))

      leadlag.dt <- rbind(leadlag.dt, data.table(
        rn = paste0(LC, ".ln_sales_tax"),
        Estimate = temp.test.est,
        `Cluster s.e.` = temp.test.se,
        `Pr(>|t|)` = temp.test.pval,
        outcome = Y,
        controls = FE,
        n_params = res1$p
      ))
    }

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
      rn = c("Pre.ln_sales_tax", "Post.ln_sales_tax", "All.ln_sales_tax"),
      Estimate = c(lead.test.est, lag.test.est, total.test.est),
      `Cluster s.e.` = c(lead.test.se, lag.test.se, total.test.se),
      `Pr(>|t|)` = c(lead.test.pval, lag.test.pval, total.test.pval),
      outcome = Y,
      controls = FE,
      n_params = res1$p
    )

    ## attach results
    flog.info("Writing results...")
    res1.dt <- data.table(coef(summary(res1)), keep.rownames=T)
    res1.dt[, outcome := Y]
    res1.dt[, controls := FE]
    res1.dt[, n_params := res1$p]
    res.table <- rbind(res.table, res1.dt, fill = T)
    res.table <- rbind(res.table, leadlag.dt, fill = T)
    res.table <- rbind(res.table, lp.dt, fill = T)
    res.table$N_module_stores <- N_module_stores
    res.table$n_params <- res1$p
    fwrite(res.table, reg.outfile)
  }
}
