# Black Sea Bass

This repository holds code for "Economic-informed stock assessments".  

Because the 
size of an individual fish determines the price of fish, we can invert this 
relationship to help fill in gaps when we do not sample the lengths of those fish.
There are 5 prevailing BSB market categories: Jumbo, Large, Medium, Small, and
Unclassified.  From 2020 to 2023, 5 to 10% of commercial landings were in the 
“Unclassified” market category; but no fish in this category were measured. We 
train a Random Forest model to transactions data from 2015-2024 and use the results
to predict the class of the Unclassified market category.



Related projects include 
"Data pull and exploration": This is a data pull and prep portion. It includes a datapull from CAMS and other sources, data exploration, and 
moderate amounts of data processing that is (hopefully) general to all projects.


"Catch shares, Environmental variation, and Port choice": There are different
regulations in each state.  Three states have a catch share program. The others 
do not; these states have a wide range of possession limits. Gear restrictions, 
mostly mesh size (trawl) or vent size (pot), are similar, but also vary by state.
How does the intersection of these regulations and changes in biomass due to 
environmental variation affect where people fish, how productive they are, and 
where they land their catch?  This may be 2 or 3 projects.

 #  Folder structure

Folder structure is mostly borrowed from the world bank's EDB. https://dimewiki.worldbank.org/wiki/Stata_Coding_Practices
Try to use forward slashes (that is C:/path/to/your/folder) instead of backslashes for unix/mac compatability. 

Your life will be easier if you organize things into a BSB_mega_folder because there are a few linked projects.

```
BSB_mega_folder/
├── READ-SSB-Lee-BSB-DataPull/  #Data pull, explore, background. 
│   ├── data_folder/              # Shared data
│ 	  ├── data_raw/	   
│ 	  ├── data_external/
│ 	  └── data_main/
│   ├── R_code/
│   ├── stata_code/
│   ├── more stuff/
├── READ-SSB-Lee-BlackSeaBass/  #Prices in stock assessment Repository
│   ├── READ-SSB-Lee-BlackSeaBass.Rproj
│   ├── data_folder
│   	├── data_raw/              # Raw data (minimal)
│ 	├── data_main/             # Final Data specific to this project
│   ├── results/
│   ├── R_code/
│   ├── stata_code/
│   └── README.md
├── PortChoice/                  #Port Choice  Repository
│   ├── PortChoice.Rproj  
│   ├── data_folder
│   	├── data_raw/              # Raw data (minimal)
│ 	├── data_main/             # Final Data specific to this project
│   ├── results/
│   ├── R_code/
│   ├── stata_code/
│   └── README.md
```




I keep each project in a separate folder.  A stata do file containing folder names get stored as a macro in stata's startup profile.do.  This lets me start working on any of my projects by opening stata and typing: 
```
do $my_project_name
```
Rstudio users using projects don't have to do this step.


# On passwords and other confidential information

Basically, you will want to store them in a place that does not get uploaded to github. 

For stata users, there is a description [here](/documentation/project_logistics.md). 

For R users, try setting and storing information in a keyring using the package ``keyring::key_set()``   You can read them in using ``keyring::key_get()`` 
If you can encrypt your [.Rprofile](/R_code/project_logistics/.Rprofile_sample), that another solution for passwords, API keys, and tokens.  

# NOAA Requirements
This repository is a scientific product and is not official communication of the National Oceanic and Atmospheric Administration, or the United States Department of Commerce. All NOAA GitHub project code is provided on an ‘as is’ basis and the user assumes responsibility for its use. Any claims against the Department of Commerce or Department of Commerce bureaus stemming from the use of this GitHub project will be governed by all applicable Federal law. Any reference to specific commercial products, processes, or services by service mark, trademark, manufacturer, or otherwise, does not constitute or imply their endorsement, recommendation or favoring by the Department of Commerce. The Department of Commerce seal and logo, or the seal and logo of a DOC bureau, shall not be used in any manner to imply endorsement of any commercial product or activity by DOC or the United States Government.”


1. who worked on this project:  Min-Yang Lee
1. when this project was created: Summer 2024 
1. what the project does: Black Sea bass related projects
1. why the project is useful:  Black Sea bass is awesome
1. how users can get started with the project: Download and follow the readme
1. where users can get help with your project:  email me or open an issue
1. who maintains and contributes to the project. Min-Yang

# License file
See here for the [license file](License.txt)
