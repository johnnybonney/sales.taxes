#' Author: John Bonney
#'
#' Plot the cohort-specific trends (across tax-change cohorts) for the 2009 Q1
#' group (data obtained from cohort_specific_2009Q1.R)

setwd("C:/Users/John Bonney/Desktop/Magne_projects/sales_taxes")

library(tidyverse)
library(zoo)
library(grid)
library(data.table)

element_grob.element_custom <- function(element, ...)  {

  segmentsGrob(c(1,0,0),
               c(0,0,1),
               c(0,0,0),
               c(0,1,1), gp=gpar(lwd=2))
}
## silly wrapper to fool ggplot2
border_custom <- function(...){
  structure(
    list(...), # this ... information is not used
    class = c("element_custom","element_blank", "element") # inheritance test workaround
  )

}

data_path <- "output/server/pi_data/increase_only/pi_all_cohorts_io_pooled_successive.csv"
outfile_figpath <- "reports/figs/pi_all_cohorts_io_pooled_successive.png"

dt <- read.csv(data_path)

dt$t <- as.yearqtr(paste0(dt$year, " Q", dt$quarter))
dt$ref_t <- as.yearqtr(paste0(dt$ref_year, " Q", dt$ref_quarter))
dt$tt_ev <- (dt$t - dt$ref_t) * 4

control_labs <- data.table(
  group = c("Treated",
            "Future restricted (in 1 quarter)",
            "Future restricted (in 2 quarters)",
            "Future restricted (in 3 quarters)",
            "Future restricted (in 4 quarters)"),
  group_Q = 0:4
)

dt <- merge(dt, control_labs, by = "group")

dt.agg <- dt %>%
  filter(between(tt_ev, -12, 4)) %>%
  group_by(group, ref_t, group_Q) %>%
  mutate(cpricei = cpricei - cpricei[tt_ev == -1 + group_Q]) %>%
  group_by(group, tt_ev, group_Q) %>%
  summarize(cpricei.agg = weighted.mean(cpricei, w = cohort_sales))

dt.test <- dt %>%
  filter(between(tt_ev, -6, 6) & ref_t <  2013.5) %>%
  group_by(group, ref_t, group_Q) %>%
  mutate(cpricei = cpricei - cpricei[tt_ev == -1 + group_Q]) %>%
  group_by(group, tt_ev, group_Q) %>%
  summarize(cpricei.agg = weighted.mean(cpricei, w = cohort_size)) %>%
  ungroup() %>%
  mutate(mygroup = factor(group_Q,levels=c("Treated",
                                           "Control (treated in 1 quarter)",
                                           "Control (treated in 2 quarters)",
                                           "Control (treated in 3 quarters)",
                                           "Control (treated in 4 quarters)")),
         treated = as.integer(group_Q == 0)) %>%
  mutate(treated = factor(treated, levels = c("Treated", "Control")))

ggplot(dt.test, mapping = aes(x = tt_ev, y = cpricei.agg, colour = group)) +
  geom_line(size = .7) +
  geom_point(size = .8) +
  geom_vline(aes(xintercept=group_Q, colour = group), linetype="22") +
  # geom_vline(xintercept = 0, color = "red", linetype = "22", alpha = .5) +
  theme_bw() +
  scale_x_continuous(expand = c(.01, -.05)) +
  labs(x = "Quarter", y = "Normalized Log Price Index", color = NULL) +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(size = 0.1, colour = 'grey'),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(colour="white", fill="white"),
    panel.spacing = unit(2, "lines"),
    panel.border = border_custom(),
    legend.position = c(0.16, 0.82),
    axis.ticks.length=unit(-0.15, "cm"),
    legend.margin = margin(t=-.2, r=-1, b=-.2, l=0, unit="cm"),
    axis.text.x = element_text(margin=unit(rep(0.3, 4), "cm")),
    axis.text.y = element_text(margin=unit(rep(0.3, 4), "cm"))
  )

ggsave(outfile_figpath, height = 120, width = 180, units = "mm")

for (pp in seq(2009, 2013.75, .25)) {
  plot.dt <- dt %>%
    filter(ref_t == pp, between(tt_ev, -4, 6)) %>%
    group_by(group) %>%
    mutate(cpricei = cpricei - cpricei[tt_ev == -2])

  myplot <- ggplot(plot.dt, mapping = aes(x = t, y = cpricei, color = group)) +
    geom_line(size = .7) +
    geom_point(size = .8) +
    geom_vline(xintercept = pp, color = "red", linetype = 1, alpha = .5) +
    theme_bw() +
    scale_x_yearqtr(format = "%Y Q%q", expand = c(.01, -.05)) +
    labs(x = "Quarter", y = "Normalized Price Index", color = "Cohort") +
    theme(
      panel.grid.major.x = element_blank(),
      panel.grid.major.y = element_line(size = 0.1, colour = 'grey'),
      panel.grid.minor = element_blank(),
      strip.background = element_rect(colour="white", fill="white"),
      panel.spacing = unit(2, "lines"),
      panel.border = border_custom(),
      legend.position = c(0.8, 0.2),
      axis.ticks.length=unit(-0.15, "cm"),
      legend.margin = margin(t=-.2, r=0, b=-.2, l=0, unit="cm"),
      axis.text.x = element_text(margin=unit(rep(0.3, 4), "cm")),
      axis.text.y = element_text(margin=unit(rep(0.3, 4), "cm"))
    )
  print(myplot)
  print(pp)
  readline(prompt="Press [enter] to continue")
}
# 2009 Q4
# 2012 Q2
# 2012 Q3
# 2012 Q4

ggplot(dt %>% filter(ref_t == 2010), mapping = aes(x = t, y = cpricei, color = group)) +
  geom_line(size = .7) +
  geom_point(size = .8) +
  geom_vline(xintercept = 2010, color = "red", linetype = 1, alpha = .5) +
  theme_bw() +
  scale_x_yearqtr(format = "%Y Q%q", limits = c(2008, 2014), expand = c(.01, -.05)) +
  labs(x = "Quarter", y = "Normalized Price Index", color = "Cohort") +
  theme(
    panel.grid.major.x = element_blank(),
    panel.grid.major.y = element_line(size = 0.1, colour = 'grey'),
    panel.grid.minor = element_blank(),
    strip.background = element_rect(colour="white", fill="white"),
    panel.spacing = unit(2, "lines"),
    panel.border = border_custom(),
    legend.position = c(0.68, 0.27),
    axis.ticks.length=unit(-0.15, "cm"),
    legend.margin = margin(t=-.2, r=0, b=-.2, l=0, unit="cm"),
    axis.text.x = element_text(margin=unit(rep(0.3, 4), "cm")),
    axis.text.y = element_text(margin=unit(rep(0.3, 4), "cm"))
  )

