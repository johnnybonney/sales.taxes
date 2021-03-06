#' Sales Taxes Project. 
#' In this code we extract the objective functions to run the Linear program for each state
#' HEr we bootstrap to get estimates of variation

library(data.table)
library(futile.logger)
library(lfe)
library(multcomp)

setwd("/project2/igaarder")

## inputs -----------------------------------------------
data.semester <- "Data/Nielsen/semester_nielsen_data.csv"

## Outputs ----------------------------------------------
output.table <- "Data/objective_state_bernestein_boot.csv"
output.table.key <- "Data/short_elas_state_boot.csv"


bernstein <- function(x, k, K){
  choose(K, k) * x^k * (1 - x)^(K - k)
}

all_pi <- fread(data.semester)

# Need to demean
all_pi[, module_by_time := .GRP, by = .(product_module_code, semester, year)]
all_pi[, L.ln_cpricei2 := ln_cpricei2 - D.ln_cpricei2]
all_pi[, dm.L.ln_cpricei2 := L.ln_cpricei2 - mean(L.ln_cpricei2, na.rm = T), by = module_by_time]
all_pi[, dm.ln_cpricei2 := ln_cpricei2 - mean(ln_cpricei2, na.rm = T), by = module_by_time]
all_pi[, dm.ln_pricei2 := ln_cpricei2 - mean(ln_pricei2, na.rm = T), by = module_by_time]

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

## Define re-scaled prices to use Bernstein polynomials in that range
min.p <- all_pi[, min(dm.ln_cpricei2)]
max.p <- all_pi[, max(dm.ln_cpricei2)]
all_pi[, r.dm.ln_cpricei2 := (dm.ln_cpricei2 - min.p)/(max.p - min.p) ]
min.p <- all_pi[, min(dm.ln_pricei2)]
max.p <- all_pi[, max(dm.ln_pricei2)]
all_pi[, r.dm.ln_pricei2 := (dm.ln_pricei2 - min.p)/(max.p - min.p) ]


# Identify taxability of module: import
taxability_panel <- fread("/project2/igaarder/Data/taxability_state_panel.csv")
# For now, make reduced rate another category
taxability_panel[, taxability := ifelse(!is.na(reduced_rate), 2, taxability)]
# We will use taxability as of December 2014
taxability_panel <- taxability_panel[(month==12 & year==2014),][, .(product_module_code, product_group_code,
                                                                    fips_state, taxability, FoodNonfood)]

## Merge to products
all_pi<- merge(all_pi, taxability_panel, by = c("product_module_code", "fips_state"))

## Run by taxability
set.seed(2019)
ids <- unique(all_pi$module_by_state)


full.data <- data.table(NULL)
charac.data <- data.table(NULL)
for (rep in 0:109) {
  
  flog.info("Iteration %s", rep)
  
  # Sample by block
  if (rep >0) {
    sampled.ids <- data.table(sample(ids, replace = T))
    setnames(sampled.ids, old= "V1", new = "module_by_state")
    
    # Merge data to actual data
    iter.data <- merge(sampled.ids, all_pi, by = c("module_by_state") , allow.cartesian = T, all.x = T)
    
  } else {
    iter.data <- all_pi
  }
  
  ## Keep only taxable items as those are whose responses we care
  
  iter.data <- iter.data[taxability == 1]
  
  
  ## Objective functions
  data.objective <- data.table(NULL)
  for (K in 10:2) {

    ### Consumer Price

    ## Objective for average elasticity
    data <- iter.data
    # Calculate berstein polynomials
    for (n in 0:(K-1)){
      data[, paste0("b",n) := bernstein(r.dm.ln_cpricei2, n, K-1)]
    }
    av.elas <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.elas[, K := K]
    av.elas[, obj := "elas"]

    ## Objective for fiscal externality
    for (n in 0:(K-1)){
      data[, paste0("b",n) := (get(paste0("b",n)))*(exp(ln_sales_tax)-1)/exp(ln_sales_tax)]
    }
    av.fe <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.fe[, K := K]
    av.fe[, obj := "fe"]
    # Put data together
    cp <- rbind(av.elas, av.fe)
    cp[, price := "consumer"]
    
    
    ### Pre-tax price
    # Calculate berstein polynomials
    for (n in 0:(K-1)){
      data[, paste0("b",n) := bernstein(r.dm.ln_pricei2, n, K-1)]
    }
    av.elas <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.elas[, K := K]
    av.elas[, obj := "elas"]

    ## Objective for fiscal externality
    for (n in 0:(K-1)){
      data[, paste0("b",n) := (get(paste0("b",n)))*(exp(ln_sales_tax)-1)/exp(ln_sales_tax)]
    }
    av.fe <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.fe[, K := K]
    av.fe[, obj := "fe"]
    # Put data together
    pt <- rbind(av.elas, av.fe)
    pt[, price := "producer"]
    
    ## All together now
    data.objective <- rbind(data.objective, cp, pt, fill = T)
  }
  # Export this data
  data.objective[, iter := rep]
  full.data <- rbind(full.data, data.objective)
  fwrite(full.data, output.table)
  
  # ## Calculate key summary statistics for MVPF
  # iter.data <- iter.data[, .(av.dm.ln_cpricei2 = weighted.mean(dm.ln_cpricei2 , w = base.sales),
  #                            av.fe2 = weighted.mean((exp(ln_sales_tax)-1)/(exp(ln_sales_tax))*dm.ln_cpricei2 , w = base.sales),
  #                            av.fe3 = weighted.mean((exp(ln_sales_tax)-1)/(exp(ln_sales_tax))*dm.ln_cpricei2^2, w = base.sales),
  #                            av.sales_tax = weighted.mean(exp(ln_sales_tax) -1 , w = base.sales),
  #                            av.ln_sales_tax = weighted.mean(ln_sales_tax , w = base.sales),
  #                            av.d_sales_tax = weighted.mean((exp(ln_sales_tax)-1)/(exp(ln_sales_tax)), w = base.sales),
  #                            av.1_d_sales_tax = weighted.mean(1/(exp(ln_sales_tax)), w = base.sales),
  #                            N = .N) , by = .(fips_state)]
  # 
  # ## Export kete charac
  # iter.data[, iter := rep]
  # charac.data <- rbind(charac.data, iter.data)
  # fwrite(charac.data, output.table.key)
  # 
}


## Run by taxability part 2
set.seed(1941)
ids <- unique(all_pi$module_by_state)
for (rep in 1:150) {
  
  flog.info("Iteration %s", rep)
  
  # Sample by block
  sampled.ids <- data.table(sample(ids, replace = T))
  setnames(sampled.ids, old= "V1", new = "module_by_state")
    
  # Merge data to actual data
  iter.data <- merge(sampled.ids, all_pi, by = c("module_by_state") , allow.cartesian = T, all.x = T)
  
  ## Keep only taxable items as those are whose responses we care
  
  iter.data <- iter.data[taxability == 1]
  
  
  # Objective functions
  data.objective <- data.table(NULL)
  for (K in 10:2) {

    ### Consumer Price

    ## Objective for average elasticity
    data <- iter.data
    # Calculate berstein polynomials
    for (n in 0:(K-1)){
      data[, paste0("b",n) := bernstein(r.dm.ln_cpricei2, n, K-1)]
    }
    av.elas <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.elas[, K := K]
    av.elas[, obj := "elas"]

    ## Objective for fiscal externality
    for (n in 0:(K-1)){
      data[, paste0("b",n) := (get(paste0("b",n)))*(exp(ln_sales_tax)-1)/exp(ln_sales_tax)]
    }
    av.fe <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.fe[, K := K]
    av.fe[, obj := "fe"]
    # Put data together
    cp <- rbind(av.elas, av.fe)
    cp[, price := "consumer"]
    
    
    ### Pre-tax price
    # Calculate berstein polynomials
    for (n in 0:(K-1)){
      data[, paste0("b",n) := bernstein(r.dm.ln_pricei2, n, K-1)]
    }
    av.elas <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.elas[, K := K]
    av.elas[, obj := "elas"]

    ## Objective for fiscal externality
    for (n in 0:(K-1)){
      data[, paste0("b",n) := (get(paste0("b",n)))*(exp(ln_sales_tax)-1)/exp(ln_sales_tax)]
    }
    av.fe <- data[ , lapply(.SD, weighted.mean, w = base.sales), by = .(fips_state), .SDcols = paste0("b",0:(K-1))]
    av.fe[, K := K]
    av.fe[, obj := "fe"]
    # Put data together
    pt <- rbind(av.elas, av.fe)
    pt[, price := "producer"]
    
    ## All together now
    data.objective <- rbind(data.objective, cp, pt, fill = T)
    
  }
  # Export this data
  data.objective[, iter := rep + 200]
  full.data <- rbind(full.data, data.objective)
  fwrite(full.data, output.table)
  
  # ## Calculate key summary statistics for MVPF
  # iter.data <- iter.data[, .(av.dm.ln_cpricei2 = weighted.mean(dm.ln_cpricei2 , w = base.sales),
  #                            av.fe2 = weighted.mean((exp(ln_sales_tax)-1)/(exp(ln_sales_tax))*dm.ln_cpricei2 , w = base.sales),
  #                            av.fe3 = weighted.mean((exp(ln_sales_tax)-1)/(exp(ln_sales_tax))*dm.ln_cpricei2^2, w = base.sales),
  #                            av.sales_tax = weighted.mean(exp(ln_sales_tax) -1 , w = base.sales),
  #                            av.ln_sales_tax = weighted.mean(ln_sales_tax , w = base.sales),
  #                            av.d_sales_tax = weighted.mean((exp(ln_sales_tax)-1)/(exp(ln_sales_tax)), w = base.sales),
  #                            av.1_d_sales_tax = weighted.mean(1/(exp(ln_sales_tax)), w = base.sales),
  #                            N = .N) , by = .(fips_state)]
  # 
  # ## Export kete charac
  # iter.data[, iter := rep + 200]
  # charac.data <- rbind(charac.data, iter.data)
  # fwrite(charac.data, output.table.key)
  
}