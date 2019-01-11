// This file contains your Data Connector logic
section AzureDataFactoryConnector;

Table.ToNavigationTable = (
    table as table,
    keyColumns as list,
    nameColumn as text,
    dataColumn as text,
    itemKindColumn as text,
    itemNameColumn as text,
    isLeafColumn as text
) as table =>
    let
        tableType = Value.Type(table),
        newTableType = Type.AddTableKey(tableType, keyColumns, true) meta 
        [
            NavigationTable.NameColumn = nameColumn, 
            NavigationTable.DataColumn = dataColumn,
            NavigationTable.ItemKindColumn = itemKindColumn, 
            Preview.DelayColumn = itemNameColumn, 
            NavigationTable.IsLeafColumn = isLeafColumn
        ],
        navigationTable = Value.ReplaceType(table, newTableType)
    in
        navigationTable;



GetAccessToken = (resourceUrl, code) =>
let
    json = Json.Document(resourceUrl),
    DirectoryId = json[TenantID],
    ClientId = json[ClientID],
    ReplyUrl = json[ReplyUrl],
    RequestBody = [client_id= ClientId,
      redirect_uri=ReplyUrl, 
      code=code,
      grant_type="authorization_code",
      resource="https://management.core.windows.net/"
    ],
    WebContentsOptions = [
        Headers=[#"Content-Type"="application/x-www-form-urlencoded",
         #"Accept" = "application/json"],
        Content = Text.ToBinary(Uri.BuildQueryString(RequestBody)),
        ManualStatusHandling = {400}
    ],
    Source = Json.Document(Web.Contents("https://login.microsoftonline.com/" & DirectoryId & "/oauth2/token?api-version=1.0", WebContentsOptions ))
in
    Source;

GetRefreshToken = (resourceUrl, code) =>
let
    json = Json.Document(resourceUrl),
    DirectoryId = json[TenantID],
    ClientId = json[ClientID],
    ReplyUrl = json[ReplyUrl],
    RequestBody = [client_id= ClientId,
      redirect_uri=ReplyUrl, 
      refresh_token=code,
      grant_type="refresh_token",
      resource="https://management.core.windows.net/"
    ],
    WebContentsOptions = [
        Headers=[#"Content-Type"="application/x-www-form-urlencoded",
         #"Accept" = "application/json"],
        Content = Text.ToBinary(Uri.BuildQueryString(RequestBody)),
        ManualStatusHandling = {400}
    ],
    Source = Json.Document(Web.Contents("https://login.microsoftonline.com/" & DirectoryId & "/oauth2/token?api-version=1.0", WebContentsOptions ))
in
    Source;




AzureDataFactoryConnector.StartLogin = (resourceUrl, state, display) =>
    let
        json = Json.Document(resourceUrl),
        DirectoryId = json[TenantID],
        ClientId = json[ClientID],
        ReplyUrl = json[ReplyUrl],
        AuthorizeUrl = "https://login.microsoftonline.com/" & DirectoryId & "/oauth2/authorize?"& Uri.BuildQueryString([
            client_id = ClientId,  
            redirect_uri = ReplyUrl,
            state = state,
            response_type = "code",
            response_mode = "query",
            prompt = "select_account"])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = ReplyUrl,
            WindowHeight = 1000,
            WindowWidth = 1200,
            Context = resourceUrl
        ];

AzureDataFactoryConnector.FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        GetAccessToken(context,Parts[code]);



AzureDataFactoryConnector.Refresh = (resourceUrl, refresh_token) => GetRefreshToken(resourceUrl, refresh_token);

GetData = (url as text, optional requestBody as record) => let
         requestHeaders = [
            #"Content-Type"="application/json",
            #"Authorization"= "Bearer " & Extension.CurrentCredential()[access_token]
        ],
        WebContentsOptions = if requestBody = null then [
            Headers = requestHeaders
        ]
        else [
            Headers = requestHeaders,
            Content = Json.FromValue(requestBody)
        ],
        JsonResult = Json.Document(Web.Contents(url, WebContentsOptions ))
    in JsonResult;


GetAdfFactoryPipelineRuns = (FactoryId as text, RunsAfter as text, RunsBefore as text) => let
    RequestBody = [
        lastUpdatedAfter=RunsAfter,
        lastUpdatedBefore=RunsBefore
    ],
    AllRawData = List.Generate(
        () => let 
            rst = GetData("https://management.azure.com" & FactoryId & "/queryPipelineRuns?api-version=2018-06-01", RequestBody)
            in [value = rst[value], nextToken = Record.FieldOrDefault(rst, "continuationToken", "last"), Process = true],
        each [Process],
        (loopContext as record) => let 
            rst = if loopContext[nextToken]="last" 
                then [value=null,last=1]
                else GetData("https://management.azure.com" & FactoryId & "/queryPipelineRuns?api-version=2018-06-01", Record.AddField(RequestBody, "continuationToken",loopContext[nextToken] ))
            in [value = rst[value], nextToken = Record.FieldOrDefault(rst, "continuationToken", "last"), Process = not Record.HasFields( rst,"last")]
     ),
    //transform List of records to Table
    #"Transformed to table" = Table.FromRecords(AllRawData),
    //remove all meta data columns , keep the data column
    #"Removed Other Columns" = Table.SelectColumns(#"Transformed to table",{"value"}),
    //transform the data column containing a list of records to table rows
    #"ExpandedListColumn" = Table.ExpandListColumn(#"Removed Other Columns", "value"),

    #"Expanded Column1" = Table.ExpandRecordColumn(#"ExpandedListColumn", "value", {"runId", "pipelineName", "parameters", "invokedBy", "runStart", "runEnd", "durationInMs", "status", "message", "lastUpdated", "annotations"}, {"Run ID", "Pipeline Name", "Parameters", "InvokedBy", "Run Start", "Run End", "Duration (ms)", "Status", "Message", "Last Updated", "Annotations"})
in
   #"Expanded Column1";

GetAdfPipelineRuns = (Factories as table) => let
    EndDate = DateTimeZone.UtcNow(),
    RunsAfter = DateTimeZone.ToText(Date.AddDays(EndDate, -7),"yyyy-MM-ddTHH:mm:ss.fffffffZ"),
    RunsBefore = DateTimeZone.ToText(EndDate,"yyyy-MM-ddTHH:mm:ss.fffffffZ"),
    Source = Table.AddColumn(Factories, "runs", each GetAdfFactoryPipelineRuns([Factory ID], RunsAfter, RunsBefore)),
    #"Removed Errors" = Table.RemoveRowsWithErrors(Source, {"runs"}),
    #"Expanded runs" = Table.ExpandTableColumn(#"Removed Errors", "runs", {"Run ID", "Pipeline Name", "Parameters", "InvokedBy", "Run Start", "Run End", "Duration (ms)", "Status", "Message", "Last Updated", "Annotations"}),
    #"Expanded InvokedBy" = Table.ExpandRecordColumn(#"Expanded runs", "InvokedBy", {"id", "name", "invokedByType"}, {"Invoked by ID", "Invoked by Name", "Invoked by Type"}),
    #"Add Parent Run ID" = Table.AddColumn(#"Expanded InvokedBy", "Parent Run ID", each if [Invoked by Type] = "PipelineActivity" then [Invoked by ID] else null),
    #"Add Schedule Name" = Table.AddColumn(#"Add Parent Run ID", "Trigger Name", each if [Invoked by Type] = "ScheduleTrigger" then [Invoked by Name] else null),
    #"Add Pipeline ID" = Table.AddColumn(#"Add Schedule Name", "Pipeline ID", each [Factory ID] & "/pipelines/" & [Pipeline Name]),
    #"Remove Invoked By ID" = Table.RemoveColumns( #"Add Pipeline ID",{"Invoked by ID", "Invoked by Name", "Pipeline Name"})
in
   #"Remove Invoked By ID";


GetAdfFactoryPipelines = (FactoryId as text) => let
    Source =  GetData("https://management.azure.com" & FactoryId & "/pipelines?api-version=2018-06-01"),
    value = Source[value],
    #"Converted to Table" = Table.FromList(value, Splitter.SplitByNothing(), {"RowData"}, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "RowData", {"id", "name", "type", "properties", "etag"}, {"Pipeline ID", "Pipeline Name", "Type", "properties", "Etag"}),
    #"Expanded properties" = Table.ExpandRecordColumn(#"Expanded Column1", "properties", {"description"}, {"Description"})
in
   #"Expanded properties";

GetAdfPipelines = (Factories as table) => let
    Source = Table.AddColumn(Factories, "pipelines", each GetAdfFactoryPipelines([Factory ID])),
    #"Removed Errors" = Table.RemoveRowsWithErrors(Source, {"pipelines"}),
    #"Expanded pipelines" = Table.ExpandTableColumn(#"Removed Errors", "pipelines", {"Pipeline ID", "Pipeline Name", "Type", "Description", "Etag"}, {"Pipeline ID", "Pipeline Name", "Type", "Description", "Etag"})

in
   #"Expanded pipelines";

GetAdfFactories = (SubscriptionID as text, optional ResourceGroup as text, optional FactoryName as text) => let
    Source =  GetData("https://management.azure.com/subscriptions/" & SubscriptionID 
        & (if ResourceGroup=null then "" else "/resourceGroups/" & ResourceGroup)
        & "/providers/Microsoft.DataFactory/factories?api-version=2018-06-01"),
    value = Source[value],
    #"Converted to Table" = Table.FromList(value, Splitter.SplitByNothing(), {"RowData"}, null, ExtraValues.Error),
    #"Expanded Column1" = Table.ExpandRecordColumn(#"Converted to Table", "RowData", {"eTag", "id", "identity", "location", "name", "properties","tags", "type"}, {"Etag", "id", "identity", "Location", "Factory Name", "properties","Tags", "type"}),
    #"Expanded properties" = Table.ExpandRecordColumn(#"Expanded Column1", "properties", {"createTime", "provisioningState", "repoConfiguration", "version"}, {"Created", "provisioningState", "repoConfiguration", "version"}),
    #"Duplicated Column" = Table.DuplicateColumn(#"Expanded properties", "id", "idparts"),
    #"Split Column by Delimiter" = Table.SplitColumn(#"Duplicated Column", "idparts", Splitter.SplitTextByDelimiter("/", QuoteStyle.None), {"idparts.1", "idparts.2", "idparts.3", "idparts.4", "idparts.5", "idparts.6"}),
    #"Changed Type" = Table.TransformColumnTypes(#"Split Column by Delimiter",{{"idparts.1", type text}, {"idparts.2", type text}, {"idparts.3", type text}, {"idparts.4", type text}, {"idparts.5", type text}, {"idparts.6", type text}}),
    #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{"idparts.5", "Resource Group"},{"id","Factory ID"}}),
    #"Removed Columns" = Table.RemoveColumns(#"Renamed Columns",{"identity","provisioningState", "repoConfiguration", "version", "type", "idparts.1", "idparts.2", "idparts.3", "idparts.4", "idparts.6"})
in
    #"Removed Columns";


[DataSource.Kind="AzureDataFactoryConnector"]
shared AzureDataFactoryConnector.TestConnection = (TenantID as text, ClientID as text, ReplyUrl as text, SubscriptionID as text) => let
    Factories =  GetAdfFactories(SubscriptionID,null,null)
in
    Factories;


[DataSource.Kind="AzureDataFactoryConnector", Publish="AzureDataFactoryConnector.Publish"]
shared AzureDataFactoryConnector.Contents = (TenantID as text, ClientID as text, ReplyUrl as text, SubscriptionID as text, optional ResourceGroup as text, optional FactoryName as text) => let
    Factories =  GetAdfFactories(SubscriptionID,ResourceGroup,FactoryName),
    FactoryIds = Table.RemoveColumns(Factories, {"Factory Name", "Resource Group","Etag","Created", "Location"}),
    objects = #table(
            {"Name", "Key", "Data", "ItemKind", "ItemName", "IsLeaf"},{
            {"Factory", "Factory",   Factories, "Table", "Table",    true} ,
            {"Pipeline", "Pipeline", GetAdfPipelines(FactoryIds), "Table", "Table", true},
            {"PipelineRuns", "PipelineRuns", GetAdfPipelineRuns(FactoryIds), "Table", "Table", true}
            }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;



// Data Source Kind description
AzureDataFactoryConnector = [
    TestConnection = (dataSourcePath) as list => 
        let
            json = Json.Document(dataSourcePath)
        in
            { "AzureDataFactoryConnector.TestConnection",json[TenantID],json[ClientID],json[ReplyUrl],json[SubscriptionID]},
    Authentication = [
        OAuth = [
            StartLogin = AzureDataFactoryConnector.StartLogin,
            FinishLogin = AzureDataFactoryConnector.FinishLogin,
            Refresh = AzureDataFactoryConnector.Refresh,
            Label ="Azure Management Auth"
        ]
    ]
];

// Data Source UI publishing description
AzureDataFactoryConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = AzureDataFactoryConnector.Icons,
    SourceTypeImage = AzureDataFactoryConnector.Icons
];

AzureDataFactoryConnector.Icons = [
    Icon16 = { Extension.Contents("AzureDataFactoryConnector16.png"), Extension.Contents("AzureDataFactoryConnector20.png"), Extension.Contents("AzureDataFactoryConnector24.png"), Extension.Contents("AzureDataFactoryConnector32.png") },
    Icon32 = { Extension.Contents("AzureDataFactoryConnector32.png"), Extension.Contents("AzureDataFactoryConnector40.png"), Extension.Contents("AzureDataFactoryConnector48.png"), Extension.Contents("AzureDataFactoryConnector64.png") }
];
