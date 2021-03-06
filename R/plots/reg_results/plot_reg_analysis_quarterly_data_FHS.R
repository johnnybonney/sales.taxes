library(data.table)
library(ggplot2)
library(zoo)

setwd("C:/Users/John Bonney/Desktop/Magne_projects/sales_taxes/output/server")

## setup -------------------
res.all <- fread("pi_data/quarterly_pi_output_FHS.csv")

## back out the lead/lag
res.all <- res.all[!grepl("\\+", rn)]
res.all$tt_event <- as.double(stringr::str_match(res.all$rn, "[0-9]"))
res.all[is.na(tt_event), tt_event := ifelse(grepl("Pre", rn), -10,
                                            ifelse(grepl("Post", rn), 9,
                                                   ifelse(grepl("All", rn), 12, 0)))]
res.all <- res.all[!rn %in% c("`unemp_rate(fit)`", "`ln_home_price(fit)`")]
res.all[, tt_event := ifelse(grepl("F", rn), -1 * tt_event, tt_event)]
# res.all[, aggregated := tt_event %in% c(-10, 9, 12)]

setnames(res.all, old = c("Estimate", "Cluster s.e."), new = c("estimate", "se"))

makeplot <- function(opts) {
  required.opts <- c("outcome", "controls", "imputed", "spec")
  if (length(setdiff(required.opts, names(opts))) != 0) {
    stop("`outcome`, `controls`, `imputed`, and `spec` required in opts")
  }

  if (opts$spec == "no X") {
    supp.dt <- data.table(tt_event = -2, estimate = 0, se = NA)
  } else {
    supp.dt <- data.table(tt_event = -2:-1, estimate = 0, se = NA)
  }

  setDT(opts)
  res.ss <- merge(res.all, opts, by = required.opts)
  res.ss <- rbind(res.ss, supp.dt, fill = TRUE)

  gg <- ggplot(data = res.ss, mapping = aes(x = tt_event, y = estimate)) +
    geom_point(size = 2, alpha = .5) +
    geom_errorbar(data = res.ss,
                  aes(ymax = estimate + 1.96 * se,
                      ymin = estimate - 1.96 * se),
                  width = .6) +
    geom_line(linetype = "55") +
    theme_bw(base_size = 16) +
    scale_x_continuous(breaks = seq(-8, 7, 2)) +
    labs(x = "Event time (quarters)", y = "Estimate", color = NULL) +
    geom_hline(yintercept = 0, color = "red", linetype = "55", alpha = .8) +
    theme(legend.position = "none",
          panel.grid.major.x = element_blank(),
          panel.grid.minor.x = element_blank())

  return(gg)
}


## cpricei plots ---------------------
cpricei.opts <- list(outcome = "ln_cpricei",
                     controls = "module_by_time",
                     imputed = TRUE)

## module by calendar-time FE
cpricei.opts$spec <- "no X"
makeplot(cpricei.opts)
ggsave("pi_figs/reg_results/lags/cpricei_moduletimeFE_imputed.png",
       height = 120, width = 200, units = "mm")

## controlling via FHS -- unemployment
cpricei.opts$spec <- "unemp_rate"
makeplot(cpricei.opts)
ggsave("pi_figs/reg_results/lags/cpricei_moduletimeFE_FHS-unemp_imputed.png",
       height = 120, width = 200, units = "mm")

## controlling via FHS -- home price
cpricei.opts$spec <- "ln_home_price"
makeplot(cpricei.opts)
ggsave("pi_figs/reg_results/lags/cpricei_moduletimeFE_FHS-homeprice_imputed.png",
       height = 120, width = 200, units = "mm")

## quantity plots ---------------------
quantity.opts <- list(outcome = "ln_quantity",
                      controls = "module_by_time",
                      imputed = TRUE)

## module by calendar-time FE
quantity.opts$spec <- "no X"
makeplot(quantity.opts)
ggsave("pi_figs/reg_results/lags/quantity_moduletimeFE_imputed.png",
       height = 120, width = 200, units = "mm")

## controlling via FHS -- unemployment
quantity.opts$spec <- "unemp_rate"
makeplot(quantity.opts)
ggsave("pi_figs/reg_results/lags/quantity_moduletimeFE_FHS-unemp_imputed.png",
       height = 120, width = 200, units = "mm")

## controlling via FHS -- home price
quantity.opts$spec <- "ln_home_price"
makeplot(quantity.opts)
ggsave("pi_figs/reg_results/lags/quantity_moduletimeFE_FHS-homeprice_imputed.png",
       height = 120, width = 200, units = "mm")


## OLD ------------------------
## module-by-time-by-region
res.quantity <- res.all[outcome == "D.ln_quantity" & controls == "region_by_module_by_time"]
ggplot(data = res.quantity, mapping = aes(x = tt_event, y = estimate, color = aggregated)) +
  geom_point(size = 2, alpha = .5) +
  geom_errorbar(data = res.quantity,
                aes(ymax = estimate + 1.96 * se,
                    ymin = estimate - 1.96 * se),
                width = .6) +
  geom_line(data = res.quantity[aggregated == F],
            linetype = "55") +
  scale_color_manual(breaks = c(TRUE, FALSE), values = c("black", "firebrick")) +
  theme_bw(base_size = 16) +
  scale_x_continuous(breaks = c(-10, seq(-8, 7, 1), 9, 12),
                     labels = c("Tot. pre", seq(-8, 7, 1), "Tot. post", "Tot. effect")) +
  labs(x = "Event time (quarters)", y = "Estimate", color = NULL) +
  geom_hline(yintercept = 0, color = "red", linetype = "55", alpha = .8) +
  scale_y_continuous(limits = c(-2, 1.25), breaks = seq(-2, 1.25, .5)) +
  theme(legend.position = "none",
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank())
ggsave("pi_figs/reg_results/lags/quantity_region_by_module_by_time.png",
       height = 120, width = 200, units = "mm")

### Grouping in pairs ----------------------------------------------------------
res.all <- fread("pi_data/quarterly_pi_output_8Lag7Lead.csv")
res.all <- res.all[controls %in% c("module_by_time", "region_by_module_by_time")]

## back out the lead/lag
res.all <- res.all[grepl("\\+", rn) | grepl("Post", rn) | grepl("Pre", rn) | grepl("All", rn)]
res.all$tt_event <- as.double(stringr::str_match(res.all$rn, "[0-9]"))
res.all[, tt_event := ifelse(grepl("F", rn), -1 * tt_event, tt_event)]
res.all[tt_event == 1, tt_event := 0]
res.all[is.na(tt_event), tt_event := ifelse(grepl("Pre", rn), -10,
                                            ifelse(grepl("Post", rn), 8,
                                                   ifelse(grepl("All", rn), 11, 0)))]
res.all[, aggregated := tt_event %in% c(-10, 8, 11)]

setnames(res.all, old = c("Estimate", "Cluster s.e."), new = c("estimate", "se"))

## cpricei plots ---------------------

## module-by-time FE
res.cpricei <- res.all[outcome == "D.ln_cpricei" & controls == "module_by_time"]
ggplot(data = res.cpricei, mapping = aes(x = tt_event, y = estimate, color = aggregated)) +
  geom_point(size = 2, alpha = .5) +
  geom_errorbar(data = res.cpricei,
                aes(ymax = estimate + 1.96 * se,
                    ymin = estimate - 1.96 * se),
                width = .6) +
  geom_line(data = res.cpricei[aggregated == F],
            linetype = "55") +
  scale_color_manual(breaks = c(TRUE, FALSE), values = c("black", "firebrick")) +
  theme_bw(base_size = 16) +
  scale_x_continuous(breaks = c(-10, seq(-8, 6, 2), 8, 11),
                     labels = c("Tot. pre", seq(-8, 6, 2), "Tot. post", "Tot. effect")) +
  labs(x = "Event time (quarters)", y = "Estimate", color = NULL) +
  geom_hline(yintercept = 0, color = "red", linetype = "55", alpha = .8) +
  scale_y_continuous(limits = c(-0.5, 1.25), breaks = seq(-0.5, 1.25, .25)) +
  theme(legend.position = "none",
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank())
ggsave("pi_figs/reg_results/lags/cpricei_pairs_module_by_time.png",
       height = 120, width = 200, units = "mm")

## module-by-time-by-region
res.cpricei <- res.all[outcome == "D.ln_cpricei" & controls == "region_by_module_by_time"]
ggplot(data = res.cpricei, mapping = aes(x = tt_event, y = estimate, color = aggregated)) +
  geom_point(size = 2, alpha = .5) +
  geom_errorbar(data = res.cpricei,
                aes(ymax = estimate + 1.96 * se,
                    ymin = estimate - 1.96 * se),
                width = .6) +
  geom_line(data = res.cpricei[aggregated == F],
            linetype = "55") +
  scale_color_manual(breaks = c(TRUE, FALSE), values = c("black", "firebrick")) +
  theme_bw(base_size = 16) +
  scale_x_continuous(breaks = c(-10, seq(-8, 6, 2), 8, 11),
                     labels = c("Tot. pre", seq(-8, 6, 2), "Tot. post", "Tot. effect")) +
  labs(x = "Event time (quarters)", y = "Estimate", color = NULL) +
  geom_hline(yintercept = 0, color = "red", linetype = "55", alpha = .8) +
  scale_y_continuous(limits = c(-0.5, 1.3), breaks = seq(-0.5, 1.25, .25)) +
  theme(legend.position = "none",
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank())
ggsave("pi_figs/reg_results/lags/cpricei_pairs_region_by_module_by_time.png",
       height = 120, width = 200, units = "mm")

## quantity plots ---------------------

## module-by-time FE
res.quantity <- res.all[outcome == "D.ln_quantity" & controls == "module_by_time"]
ggplot(data = res.quantity, mapping = aes(x = tt_event, y = estimate, color = aggregated)) +
  geom_point(size = 2, alpha = .5) +
  geom_errorbar(data = res.quantity,
                aes(ymax = estimate + 1.96 * se,
                    ymin = estimate - 1.96 * se),
                width = .6) +
  geom_line(data = res.quantity[aggregated == F],
            linetype = "55") +
  scale_color_manual(breaks = c(TRUE, FALSE), values = c("black", "firebrick")) +
  theme_bw(base_size = 16) +
  scale_x_continuous(breaks = c(-10, seq(-8, 6, 2), 8, 11),
                     labels = c("Tot. pre", seq(-8, 6, 2), "Tot. post", "Tot. effect")) +
  labs(x = "Event time (quarters)", y = "Estimate", color = NULL) +
  geom_hline(yintercept = 0, color = "red", linetype = "55", alpha = .8) +
  scale_y_continuous(limits = c(-2, 1.25), breaks = seq(-2, 1.25, .5)) +
  theme(legend.position = "none",
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank())
ggsave("pi_figs/reg_results/lags/quantity_pairs_module_by_time.png",
       height = 120, width = 200, units = "mm")

## module-by-time-by-region
res.quantity <- res.all[outcome == "D.ln_quantity" & controls == "region_by_module_by_time"]
ggplot(data = res.quantity, mapping = aes(x = tt_event, y = estimate, color = aggregated)) +
  geom_point(size = 2, alpha = .5) +
  geom_errorbar(data = res.quantity,
                aes(ymax = estimate + 1.96 * se,
                    ymin = estimate - 1.96 * se),
                width = .6) +
  geom_line(data = res.quantity[aggregated == F],
            linetype = "55") +
  scale_color_manual(breaks = c(TRUE, FALSE), values = c("black", "firebrick")) +
  theme_bw(base_size = 16) +
  scale_x_continuous(breaks = c(-10, seq(-8, 6, 2), 8, 11),
                     labels = c("Tot. pre", seq(-8, 6, 2), "Tot. post", "Tot. effect")) +
  labs(x = "Event time (quarters)", y = "Estimate", color = NULL) +
  geom_hline(yintercept = 0, color = "red", linetype = "55", alpha = .8) +
  scale_y_continuous(limits = c(-2, 1.25), breaks = seq(-2, 1.25, .5)) +
  theme(legend.position = "none",
        panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank())
ggsave("pi_figs/reg_results/lags/quantity_pairs_region_by_module_by_time.png",
       height = 120, width = 200, units = "mm")
