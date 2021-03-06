### In this R-file we create a semesterly file with all Nielsen data and tax rate information

library(data.table)
library(lfe)
library(futile.logger)
library(AER)
library(readstata13)


setwd("/project2/igaarder")

## useful filepaths ------------------------------------------------------------
sales_data_path <- "Data/sales_quarterly_2006-2016.csv"
monthly_tax_path <- "Data/county_monthly_tax_rates.csv"
all_goods_pi_path <- "Data/all_nielsen_data_2006_2016_semesterly_taxM6.csv"
FE_pindex_path <- "Data/Nielsen/Pindex_FE_yearly_all_years.csv"
output_yearly <- "Data/Nielsen/yearly_nielsen_data.csv"
exemption_path <- "Data/Module_exemptions_by_state.dta"
#taxable_pi_path <- "Data/Nielsen/price_quantity_indices_taxableitems_2006-2016.csv"
#eventstudy_tr_path <- "Data/event_study_tr_groups_comprehensive_firstonly_no2012q4_2013q1q2.csv"
#tr_groups_path <- "Data/tr_groups_comprehensive_firstonly_no2012q4_2013q1q2.csv"


######## GOAL: Make quarterly data where tax rate is tax rate in third month of each quarter (all_nielsen_data_2006_2016_quarterly_taxM3.csv)
#### First Step: Make quarterly tax data (where tax rate in each quarter is measured as the tax rate in the third month)
monthly.tax <- fread(monthly_tax_path)

# Tax rates to impute 2006, 2007, 2013, and 2014
pre.2008.tax <- monthly.tax[year == 2008 & month == 1,]
post.2014.tax <- monthly.tax[year == 2014 & month == 12,]
pre.2008.tax <- pre.2008.tax[, c("fips_state", "fips_county", "sales_tax", "state_tax", "county_tax")]
post.2014.tax <- post.2014.tax[, c("fips_state", "fips_county", "sales_tax", "state_tax", "county_tax")]

#
pre.2008.semester <- data.table(NULL)
for (X in 2006:2007) {
  for (Y in 1:2) {
    pre.2008.tax[, year := X]
    pre.2008.tax[, semester := Y]
    pre.2008.semester <- rbind(pre.2008.semester, pre.2008.tax)
  }
}

#
post.2014.semester <- data.table(NULL)
for (X in 2015:2016) {
  for (Y in 1:2) {
    post.2014.tax[, year := X]
    post.2014.tax[, semester := Y]
    post.2014.semester <- rbind(post.2014.semester, post.2014.tax)
  }
}



monthly.tax <- monthly.tax[, semester := ceiling((month/12)*2)]
monthly.tax <- monthly.tax[, month := month - (semester - 1)*6] ## nth month in the semester (1, 2, 3, 4, 5 or 6)

semesterly.tax <- monthly.tax[, list(sales_tax = sales_tax[month == 6], state_tax = state_tax[month == 6], county_tax = county_tax[month == 6]), by = .(fips_state, fips_county, year, semester)]
semesterly.tax <- rbind(pre.2008.semester, semesterly.tax)
semesterly.tax <- rbind(semesterly.tax, post.2014.semester)


#### Second Step: Import price index and sales data at quarterly level
nonfood_pi <- read.dta13("Data/Nielsen/Price_quantity_indices_nonfood.dta")
nonfood_pi <- as.data.table(nonfood_pi)

food_pi <- fread("Data/Nielsen/price_quantity_indices_food.csv")
food_pi[, c("fips_state", "fips_county") := NULL]

all_pi <- rbind(food_pi, nonfood_pi)
all_pi <- all_pi[year <= 2016]
rm(nonfood_pi, food_pi)
gc()


### attach county and state FIPS codes, sales ----------------------------------
sales_data <- fread(sales_data_path)
sales_data <- sales_data[, .(store_code_uc, product_module_code, fips_county,
                             fips_state, quarter, year, sales)]
sales_data <- sales_data[year <= 2016]

all_pi <- merge(all_pi, sales_data, by = c("store_code_uc", "quarter", "year",
                                           "product_module_code" ))
rm(sales_data)
gc()

###
# Balance the sample (so that observations appear in every quarter)
## balance on store-module level (only keep observations that are in every quarter)
keep_store_modules <- all_pi[, list(n = .N),
                             by = .(store_code_uc, product_module_code)]
keep_store_modules <- keep_store_modules[n == (2016 - 2005) * 4]

setkey(all_pi, store_code_uc, product_module_code)
setkey(keep_store_modules, store_code_uc, product_module_code)

all_pi <- all_pi[keep_store_modules]
setkey(all_pi, fips_county, fips_state)
###

###
#Collapse at semesterly-level
all_pi <- all_pi[, semester := ceiling((quarter/4)*2)]
all_pi <- all_pi[, list(pricei = mean(pricei), sales = mean(sales)), by = .(store_code_uc, product_module_code, fips_state, fips_county, year, semester)]



### Third Step: Merge sales and price index data to tax data
all_pi[, fips_county := ifelse(fips_state == 51 & fips_county == 13, 59, fips_county)] ## It looks like FIPS 51013 in Nielsen data (Arlington, VA) should match to 51059 (Fairfax, VA) in sales tax data because of a change in FIPS code (multiple counties merged)

all_pi <- merge(all_pi, semesterly.tax, by = c("fips_state", "fips_county",
                                              "year", "semester"),
                all.x = T)
rm(semesterly.tax)


### Fouth step : Merge "state-level exemption file"
exemption.file <- read.dta13(exemption_path)
exemption.file <- exemption.file[, c("fips_state_code", "product_module_code", "taxable")]
names(exemption.file) <- c("fips_state", "product_module_code", "taxable")
all_pi <- merge(all_pi, exemption.file, by = c("fips_state", "product_module_code"), all.x = T)


### Fifth step: Take care of the items whose taxability status changed over the years
all_pi[taxable == 2 & fips_state == 5 & year <= 2010, "sales_tax"] <- 0.02
all_pi[taxable == 2 & fips_state == 5 & year <= 2010, "taxable"] <- 1

all_pi[taxable == 2 & fips_state == 5 & year >= 2011, "sales_tax"] <- 0.015
all_pi[taxable == 2 & fips_state == 5 & year >= 2011, "taxable"] <- 1

all_pi[taxable == 2 & fips_state == 8 & (year <= 2009), "taxable"] <- 0 ## month <= 4
all_pi[taxable == 2 & fips_state == 8 & (year >= 2011 | year == 2010), "taxable"] <- 1 ## month >= 5

all_pi[taxable == 2 & fips_state == 17, "sales_tax"] <- 0.01
all_pi[taxable == 2 & fips_state == 17, "taxable"] <- 1

all_pi[taxable == 3 & fips_state == 17 & (year <= 2008 | (year == 2009 & semester == 1)), "sales_tax"] <- 0.01 ##month <= 8
all_pi[taxable == 3 & fips_state == 17 & (year <= 2008 | (year == 2009 & semester == 1)), "taxable"] <- 1 ## month <= 8
all_pi[taxable == 3 & fips_state == 17 & (year >= 2010 | (year == 2009 & semester == 2)), "taxable"] <- 1 ## month >= 9

all_pi[taxable == 2 & fips_state == 23 & (year <= 2012 | (year == 2013 & semester == 1)), "taxable"] <- 0 ## month <= 9
all_pi[taxable == 2 & fips_state == 23 & (year >= 2014 | (year == 2013 & semester == 2)), "taxable"] <- 1 ## month >= 10

all_pi[taxable == 2 & fips_state == 29, "sales_tax"] <- 0.01225
all_pi[taxable == 2 & fips_state == 29, "taxable"] <- 1

all_pi[taxable == 2 & fips_state == 37, "sales_tax"] <- 0.02
all_pi[taxable == 2 & fips_state == 37, "taxable"] <- 1

all_pi[taxable == 2 & fips_state == 44 & (year <= 2010 | (year == 2011 & semester == 1)), "taxable"] <- 0  ## month <= 9
all_pi[taxable == 2 & fips_state == 44 & (year >= 2012 | (year == 2011 & semester == 2)), "taxable"] <- 1 ## month >= 10

all_pi[taxable == 2 & fips_state == 47 & (year <= 2012 | (year == 2013 & semester == 1)), "sales_tax"] <- 0.0525  ## month <= 6
all_pi[taxable == 2 & fips_state == 47 & (year <= 2012 | (year == 2013 & semester == 1)), "taxable"] <- 1 ## month <= 6

all_pi[taxable == 2 & fips_state == 47 & (year >= 2014 | (year == 2013 & semester == 2)), "sales_tax"] <- 0.05 ## month >= 7
all_pi[taxable == 2 & fips_state == 47 & (year >= 2014 | (year == 2013 & semester == 2)), "taxable"] <- 1 ## month >= 7

all_pi[taxable == 2 & fips_state == 49, "sales_tax"] <- 0.03
all_pi[taxable == 2 & fips_state == 49, "taxable"] <- 1

all_pi[taxable == 2 & fips_state == 51, "sales_tax"] <- 0.015
all_pi[taxable == 2 & fips_state == 51, "taxable"] <- 1

#all_pi[taxable == 2 & fips_state == 53 & (year <= 2009 | (year == 2010 & (quarter < 2 | quarter > 3)) | year >= 2011), "taxable"] <- 0  ## (month <= 5 | month == 12)
#all_pi[taxable == 2 & fips_state == 53 & (year == 2010 & ( quarter >= 2 & quarter <= 3)), "taxable"] <- 1 ## ( month >= 6 & month <= 11)
all_pi[taxable == 2 & fips_state == 53, "taxable"] <- 0

all_pi[taxable == 2 & fips_state == 54 & (year < 2008 | (year == 2008 & semester == 1)), "sales_tax"] <- 0.04  ## month <= 6
all_pi[taxable == 2 & fips_state == 54 & (year < 2008 | (year == 2008 & semester == 1)), "taxable"] <- 1 ## month <= 6

all_pi[taxable == 2 & fips_state == 54 & ((year == 2008 & semester == 2) | (year >= 2009 & year <= 2011)), "sales_tax"] <- 0.03 ## month >= 7
all_pi[taxable == 2 & fips_state == 54 & ((year == 2008 & semester == 2) | (year >= 2009 & year <= 2011)), "taxable"] <- 1 ## month >= 7

all_pi[taxable == 2 & fips_state == 54 & (year == 2012 & semester == 1), "sales_tax"] <- 0.02  ## month <= 6
all_pi[taxable == 2 & fips_state == 54 & (year == 2012 & semester == 1), "taxable"] <- 1  ## month <= 6

all_pi[taxable == 2 & fips_state == 54 & ((year == 2012 & semester == 2) | (year == 2013 & semester == 1)), "sales_tax"] <- 0.01  ## ((year == 2012 & month >= 7) | (year == 2013 & month <= 6))
all_pi[taxable == 2 & fips_state == 54 & ((year == 2012 & semester == 2) | (year == 2013 & semester == 1)), "taxable"] <- 1 ## ((year == 2012 & month >= 7) | (year == 2013 & month <= 6))

all_pi[taxable == 2 & fips_state == 54 & ((year == 2013 & semester == 2) | year >= 2014), "taxable"] <- 0  ## month >= 7

## Check that all taxable is either 0 or 1
unique(all_pi$taxable)


## Set tax rate of non-taxable goods to zero
all_pi[, sales_tax := sales_tax*taxable]


fwrite(all_pi, all_goods_pi_path)
rm(all_pi)

