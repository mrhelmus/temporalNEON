# Original code from Mariana Perez Rocha
######## NEON macroinvertebrate data download, cleaning, and tidying################

##clear out environment
rm(list = ls())
gc()
gc(reset = T)


# set options
options(stringsAsFactors = FALSE)
options(scipen = 999)

#set directory
datadir <- "C:/Users/mpere/Desktop/NEON"
setwd(datadir)


#load packages
require(neonUtilities) 
require(stringr)
require(dplyr)
require(lubridate)
require(tidyverse)


# macroinverts dpid
my_dpid <- 'DP1.20120.001'

##sites meeting the criteria (for macroinverts more than 2 years of sampling)
# my aquatic sites
my_site_list <- c('ARIK','BARC','BLWA','CARI','COMO','CRAM','CUPE','GUIL','HOPB',
                  'KING','LECO','LEWI','MAYF','OKSR','POSE','PRIN','PRLA','PRPO',
                  'REDB','SUGG','TOMB','TOOK','WALK')


#download NEON data using API
inv_allTabs <- loadByProduct(dpID = my_dpid, 
                             site = my_site_list,
                             package = "expanded", check.size = FALSE)
labels(inv_allTabs)


# get taxon table from API, may take a few minutes to load
full_taxon_table <- neonUtilities::getTaxonTable('MACROINVERTEBRATE')

# make ordered taxon_rank_list for a reference (subspecies is smallest rank, kingdom is largest)
taxon_rank_list_ordered <- c('kingdom', 'subkingdom',
                             'infrakingdom', 'superphylum', 'phylum', 'subphylum', 'infraphylum',
                             'superdivision', 'division', 'subdivision', 'infradivision', 'parvdivision',
                             'superclass', 'class', 'subclass', 'infraclass', 'superorder',
                             'order', 'suborder', 'infraorder', 'section', 'subsection',
                             'superfamily', 'family', 'subfamily', 'tribe', 'subtribe',
                             'genus','subgenus','speciesGroup','species','subspecies') %>% rev()
#explore data
names(inv_allTabs )
names(inv_allTabs$inv_taxonomyProcessed)


# getting table of location into a data.frame (lat, long, elevation)
table_location <- inv_allTabs$inv_fieldData %>%
  select(namedLocation, decimalLatitude, decimalLongitude, elevation) %>%
  distinct() %>%
  rename(
    location_id = namedLocation,
    latitude = decimalLatitude,
    longitude = decimalLongitude
    ) 

write.csv(table_location, file = 
            'all_inverts_table_location.csv', row.names = F)

#merge/join tables: processing macroinverts data to get to density/abundance 

inv_dat <- left_join(inv_allTabs$inv_taxonomyProcessed, inv_allTabs$inv_fieldData, 
                     by = c('sampleID')) %>% 
  mutate(den = estimatedTotalCount/benthicArea) %>% 
  mutate(scientificName = forcats::fct_explicit_na(scientificName)) %>%
  dplyr::filter(sampleCondition == "condition OK")


# get rid of duplicate col names and .x suffix after joining table with the same col names
inv_dat <- inv_dat[,!grepl('\\.y',names(inv_dat))]
names(inv_dat) <- gsub('\\.x','',names(inv_dat))

# get genus and finer resolution using ordered taxon_rank_list
inv_dat$taxonRank_ordered <- factor(
  inv_dat$taxonRank,
  levels = taxon_rank_list_ordered,
  ordered = TRUE) 

# get all records that have rank <= genus, where genus is not NA or blank
inv_dat_fine <- inv_dat %>%
  filter(taxonRank_ordered <= 'genus') %>%
  filter(!is.na(genus), genus != '')

# this table has all variables and it's not in a spread format yet
View(inv_dat_fine)

# grouping variables for aggregating density/abundance. Come back here if other vars are need in the final table.
#for now, it's easier to keep simple like this in order to get one entry per site per row (species per sites summed)
my_grouping_vars <- c('siteID','genus','collectDate')


# aggregate densities for each genus group, pull out year and month from collectDate, then
#excluding collectDate
inv_dat_aggregate <- inv_dat_fine %>%
  select(one_of(my_grouping_vars), den) %>%
  mutate(
    year = collectDate %>% lubridate::year(),
    month = collectDate %>% lubridate::month()
  ) %>%
  group_by_at(vars(my_grouping_vars, year, month)) %>%
  summarize(
    abundance = sum(den)) %>% 
  ungroup()


View(inv_dat_aggregate)


###put in the formats required for codyn and BAT

inv_dat_aggregate <- inv_dat_fine %>%
  select(one_of(my_grouping_vars), den) %>%
  group_by_at(vars(my_grouping_vars)) %>%
  summarize(
    abundance = sum(den)) %>% 
  ungroup()

View(inv_dat_aggregate)


## Codyn (year and month)
write.csv(inv_dat_aggregate , file = 
            'macroinverts_table_abundance_codyn.csv', row.names = F)


##BAT year

agregate_year_BAT <- inv_dat_aggregate%>% 
  group_by(genus,year,siteID) %>%
  summarise(abund = mean(abundance))%>%
  spread(genus,abund, fill = 0)

View(agregate_year_BAT)

write.csv(agregate_year_BAT , file = 
            'macroinverts_table_abundance_year_BAT.csv', row.names = F)


## BAT month

# make wide first, filling with abundance, making the 'bout' (format year+month) to be used in BAT
inv_dat_wide <- inv_dat_aggregate %>%
  tidyr::spread(genus, abundance, fill = 0)%>% 
  unite(bout,'year':'month', na.rm = TRUE, remove = FALSE)%>%
  dplyr::select(-collectDate)


View(inv_dat_wide)

write.csv(inv_dat_wide, file = 
            'macroinverts_table_abundance_month_BAT.csv', row.names = F)