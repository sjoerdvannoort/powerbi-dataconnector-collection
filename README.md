# Introduction

The custom data connectors for Power BI in this project are primarily meant as comprehensive examples on how to consume data from REST APIs and how to deal with authentication and paging. 

If however you're just interested in using the data connectors you can simply download the mez files and copy them to your local Custom Connectors folder.

All data connectors implement TestConnection and can be used in the Power BI service and refreshed through a gateway.

For more information on custom data connectors for Power BI, please refer to:

* [Starting to Develop Custom Connectors](https://docs.microsoft.com/en-us/power-query/startingtodevelopcustomconnectors)
* [Microsoft Data Connectors](https://github.com/Microsoft/DataConnectors)

# DatabricksRunsConnector

This connector is an example on how to consume a REST API that requires an authorization header with a key and that implements paging.

This connector is a wrapper for the [(Azure) Databricks Jobs API (2.0) Runs List method](https://docs.azuredatabricks.net/api/latest/jobs.html#runs-list). 
Using it enables the user to get a list of all recent notebook runs even if they were triggered from an Azure Data Factory pipeline. 
The result contains the result and timing information along with a URL for more details.

The max pages parameter determines how many times the service is called. The page size is 100 job runs, so a max page size of 10 will return the 1000 most recent job runs. 

To connect you will need a [personal acces token](https://docs.azuredatabricks.net/api/latest/authentication.html) for authentication. 
You will also need to provide the host name of the databricks service you are using and the service name. 
The latter is not used for connecting, but needed to be able to store multiple credentials if you are using multiple databricks services in the same region (thus on the same host).

# WorldBankConnector

This connector is an example on how to consume a REST API that does not require authentication and that implements paging. 
The connector also implements a navigation table.

When connecting you will be prompted for the data you want to retrieve. Below are examples for getting population and GDP information:

| Parameter | Example 1 | Example 2
| --- | --- | ---
| indicator | SP.POP.TOTL | NY.GDP.MKTP.PP.CD
| countries | all | chn;bra;ind;rus
| dateRange | 2017:2017 | 1998:2017

For more information, consult the [world bank web site](https://datahelpdesk.worldbank.org/knowledgebase/articles/898581-basic-api-call-structures)
