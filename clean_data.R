##############
# Clean Data #
##############

#Jonathan Auerbach
#September 1, 2017
#script makes tickets.csv from raw traffic violations data
## for reference purposes

library("tidyverse")
library("stringr")
library("rgdal")
library("sp")

#read raw data of parking and moving violations
##parking violations from https://data.cityofnewyork.us/dataset/c284-tqph
park2014 <- read_csv(
  "Parking_Violations_Issued_-_Fiscal_Year_2014__August_2013___June_2014_.csv",
  col_types = cols(`Violation Legal Code` = col_character(),
                   `Summons Number` = col_character(),
                   `Unregistered Vehicle?` = col_character(),
                   `Vehicle Expiration Date` = col_character(),
                   `Date First Observed` = col_character(),
                   `Issue Date` = col_date(format = "%m/%d/%Y")))

park2015 <- read_csv(
  "Parking_Violations_Issued_-_Fiscal_Year_2015.csv",
  col_types = cols(`Violation Legal Code` = col_character(),
                   `Summons Number` = col_character(),
                   `Unregistered Vehicle?` = col_character(),
                   `Vehicle Expiration Date` = col_character(),
                   `Date First Observed` = col_character(),
                   `Issue Date` = col_date(format = "%m/%d/%Y")))

park2016 <- read_csv(
  "Parking_Violations_Issued_-_Fiscal_Year_2016.csv",
  col_types = cols(`Violation Legal Code` = col_character(),
                   `Summons Number` = col_character(),
                   `Unregistered Vehicle?` = col_character(),
                   `Vehicle Expiration Date` = col_character(),
                   `Date First Observed` = col_character(),
                   `Issue Date` = col_date(format = "%m/%d/%Y")))

parking <- bind_rows(park2014, park2015, park2016) %>% 
  filter(format(`Issue Date`, "%Y") %in% 2014:2015)

rm(list = c("park2014", "park2015", "park2016"))

#moving violations from https://data.ny.gov/dataset/q4hy-kbtf
## OFFICER_ID and VIOL_DTE obtained via FOIL with NYS DMV
moving <- read_csv("F16_4811_TKTS.csv", 
                   n_max = 14240928,
                   col_types = cols(
                     `VIOL_DTE` = col_date(format = "%m/%d/%Y %H:%M:%S"))) %>%
          filter(format(`VIOL_DTE`, "%Y") %in% 2014:2015,
                 POLICE_AGENCY == "NYC POLICE DEPT") %>%
          mutate(OFFICER_ID = parse_number(OFFICER_ID))

#impute violation description for parking violations
# see http://www1.nyc.gov/site/finance/vehicles/services-violation-codes.page
## for detailed description
code_dictionary <- parking %>% 
  select(`Violation Code`, `Violation Description`) %>%
  unique() %>%
  na.omit() %>%
  arrange(`Violation Description`) %>%
  group_by(`Violation Code`) %>%
  summarise(`Violation Description Imputed` = str_c(`Violation Description`, 
                                                    collapse = "/"))

parking <- parking %>% left_join(code_dictionary, by = "Violation Code") 
parking <- parking %>% mutate(`Violation Description Imputed` = 
                                  ifelse(is.na(`Violation Description Imputed`),
                                         `Violation Code`,
                                         `Violation Description Imputed`))

#combine datasets
tickets <- bind_rows(
  data_frame(id = parking$`Issuer Code`,
             command = parking$`Issuer Command`,
             date = parking$`Issue Date`,
             violation = toupper(parking$`Violation Description Imputed`)),
  data_frame(id = moving$OFFICER_ID,
             command = moving$Command,
             date = moving$VIOL_DTE,
             violation = str_c(moving$VIOL_CHRGD, moving$`VT DESC`, sep = "-")))

#precint shapefile from 
## https://www1.nyc.gov/site/planning/data-maps/open-data/districts-download-metadata.page
## need http://www.mapshaper.org/ 
precinct <- readOGR("nypp","nypp")
tickets <- tickets %>% 
  filter(!grepl("[^0-9]", command)) %>%
  mutate(command = parse_number(command)) %>%
  filter(command %in% unique(precinct@data$Precinct))

#read collisions
# data from
# https://data.cityofnewyork.us/Public-Safety/NYPD-Motor-Vehicle-Collisions/h9gi-nx95
crashes <- read_csv("NYPD_Motor_Vehicle_Collisions.csv",
                    col_types = cols(DATE = col_date(format = "%m/%d/%Y"))) %>%
          filter(!is.na(LONGITUDE),
                 format(DATE, "%Y") %in% 2014:2015)

NAD83 <- "+proj=lcc +lat_1=40.66666666666666 +lat_2=41.03333333333333 +lat_0=40.16666666666666 
+lon_0=-74 +x_0=300000 +y_0=0 +datum=NAD83 +units=us-ft +no_defs +ellps=GRS80
+towgs84=0,0,0"
WGS84 <- "+proj=longlat +datum=WGS84 +no_defs +ellps=WGS84 +towgs84=0,0,0"

crashes <- crashes %>%
  mutate(Precinct = crashes %>%
           select(LONGITUDE, LATITUDE) %>%
           cbind() %>%
           SpatialPoints(., CRS(WGS84)) %>%
           spTransform(CRS(NAD83)) %>%
           over(precinct) %>%
           select(Precinct) %>%
           pull())

crashes <- crashes %>%
  group_by(Precinct, DATE) %>%
  count() %>%
  right_join(crashes %>% expand(DATE, Precinct), 
             by = c("Precinct", "DATE")) %>%
  mutate(n = ifelse(is.na(n), 0, n))