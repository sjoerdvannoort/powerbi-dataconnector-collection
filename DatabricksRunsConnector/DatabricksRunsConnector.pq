// This file contains your Data Connector logic
section DatabricksRunsConnector;

GetDatabricksApiPage = (hostUrl as text, page as number) as any =>
    let
        requestHeaders = [
            #"Content-Type"="application/json",
            #"Authorization"= "Bearer " & Extension.CurrentCredential() [Key]
        ],
        WebContentsOptions = [
            Headers = requestHeaders
        ],
        url = hostUrl & "/api/2.0/jobs/runs/list?completed_only=true&limit=100&offset=" & Number.ToText((page -1 ) * 100),
        JsonResult = Json.Document(Web.Contents(url, WebContentsOptions )),
        //create result record
        pageResult = [hasMore = JsonResult[has_more], data = JsonResult[runs], page=page]
    in 
        pageResult;

DatabricksRunsType = type function (
    hostUrl as (type text meta [
        Documentation.FieldCaption = "Host Url",
        Documentation.FieldDescription = "Databricks service URL",
        Documentation.SampleValues = {"https://northeurope.azuredatabricks.net", "https://westeurope.azuredatabricks.net"}
    ]),
    serviceName as (type text meta [
        Documentation.FieldCaption = "Databricks service name",
        Documentation.FieldDescription = "Not used to connect, but as unique reference when storing the credentials."
    ]),
    optional maxPages as (type number meta [
        Documentation.FieldCaption = "Maximum pages",
        Documentation.FieldDescription = "The maximum number of times the REST method will be called. The default value is 10."
    ]))
    as table meta [
        Documentation.Name = "Databricks runs",
        Documentation.LongDescription = "Returns the most recent Databricks job runs"
    ];


DatabricksRunsImpl = (hostUrl as text, serviceName as text, optional maxPages as number) as table => 
    let
        effMaxPages = if maxPages = null then 10 else maxPages,
        allPagesData = List.Generate(
            () => GetDatabricksApiPage(hostUrl,1),
            each [page]<=effMaxPages and [hasMore],
            each GetDatabricksApiPage(hostUrl,[page] +1)
        ),
        //transform List of records to Table
        #"Transformed to table" = Table.FromRecords(allPagesData),
        //remove all meta data columns , keep the data column
        #"Removed Other Columns" = Table.SelectColumns(#"Transformed to table",{"data"}),
        //transform the data column containing a list of records to table rows
        #"ExpandedListColumn" = Table.ExpandListColumn(#"Removed Other Columns", "data"),
        #"Expanded data" = Table.ExpandRecordColumn(#"ExpandedListColumn", "data", {"job_id", "run_id", "number_in_job", "state", "task", "cluster_spec", "cluster_instance", "start_time", "setup_duration", "execution_duration", "cleanup_duration", "creator_user_name", "run_name", "run_page_url", "run_type"}, {"job_id", "run_id", "number_in_job", "state", "task", "cluster_spec", "cluster_instance", "start_time", "setup_duration", "execution_duration", "cleanup_duration", "creator_user_name", "run_name", "run_page_url", "run_type"}),
        #"Expanded state" = Table.ExpandRecordColumn(#"Expanded data", "state", {"life_cycle_state", "result_state", "state_message"}, {"life_cycle_state", "result_state", "state_message"}),
        #"Expanded task" = Table.ExpandRecordColumn(#"Expanded state", "task", {"notebook_task"}, {"notebook_task"}),
        #"Expanded cluster_spec" = Table.ExpandRecordColumn(#"Expanded task", "cluster_spec", {"existing_cluster_id"}, {"existing_cluster_id"}),
        #"Expanded cluster_instance" = Table.ExpandRecordColumn(#"Expanded cluster_spec", "cluster_instance", {"cluster_id", "spark_context_id"}, {"cluster_id", "spark_context_id"}),
        #"Expanded notebook_task" = Table.ExpandRecordColumn(#"Expanded cluster_instance", "notebook_task", {"notebook_path"}, {"notebook_path"}),
        #"Changed Type" = Table.TransformColumnTypes(#"Expanded notebook_task",{{"start_time", Int64.Type}, {"setup_duration", Int64.Type}, {"job_id", Int64.Type}, {"run_id", Int64.Type}, {"number_in_job", Int64.Type}, {"execution_duration", Int64.Type}, {"cleanup_duration", Int64.Type}}),
        //calculate datetime from unix format datetime
        #"Added start_datetime" = Table.AddColumn(#"Changed Type", "start_datetime", each #datetime(1970, 1, 1, 0, 0, 0) + #duration(0, 0, 0, [start_time]/1000)),
        #"Changed Type start_datetime" = Table.TransformColumnTypes(#"Added start_datetime",{{"start_datetime", type datetime}}),
        #"Removed start_time" = Table.RemoveColumns(#"Changed Type start_datetime",{"start_time"})
    in
        #"Removed start_time";

[DataSource.Kind="DatabricksRunsConnector", Publish="DatabricksRunsConnector.Publish"]
shared DatabricksRunsConnector.Contents = Value.ReplaceType(DatabricksRunsImpl,DatabricksRunsType);

shared DatabricksRunsConnector.TestConnectionImpl = (hostUrl as text) =>
     let
        requestHeaders = [
            #"Content-Type"="application/json",
            #"Authorization"= "Bearer " & Extension.CurrentCredential() [Key]
        ],
        WebContentsOptions = [
            Headers = requestHeaders
        ],
        url = hostUrl & "/api/2.0/jobs/runs/list?completed_only=true&limit=10&offset=0",
        JsonResult = Json.Document(Web.Contents(url, WebContentsOptions ))
    in JsonResult;



// Data Source Kind description
DatabricksRunsConnector = [
    TestConnection = (dataSourcePath) as list => 
        let
            json = Json.Document(dataSourcePath),
            hostUrl = json[hostUrl]
        in
            { "DatabricksRunsConnector.TestConnectionImpl",hostUrl},
    Authentication = [
        Key = [
            KeyLabel = "Personal Access Token",
            Label = "Databricks authentication"
        ]
    ]
    //Do NOT supply a label to enable identification of datasource in Power BI dialogue
    //Label = Extension.LoadString("DataSourceLabel") 
];

// Data Source UI publishing description
DatabricksRunsConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = DatabricksRunsConnector.Icons,
    SourceTypeImage = DatabricksRunsConnector.Icons
];

DatabricksRunsConnector.Icons = [
    Icon16 = { Extension.Contents("DatabricksRunsConnector16.png"), Extension.Contents("DatabricksRunsConnector20.png"), Extension.Contents("DatabricksRunsConnector24.png"), Extension.Contents("DatabricksRunsConnector32.png") },
    Icon32 = { Extension.Contents("DatabricksRunsConnector32.png"), Extension.Contents("DatabricksRunsConnector40.png"), Extension.Contents("DatabricksRunsConnector48.png"), Extension.Contents("DatabricksRunsConnector64.png") }
];
