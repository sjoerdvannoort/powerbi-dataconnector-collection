// This file contains your Data Connector logic
section WorldBankConnector;

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


GetWorldBankPage = (page as text, query as text, optional queryparms as text) =>
    let
        //conactenate url, call web api, cast as Json
        url ="http://api.worldbank.org/v2/" &  query & "?format=json&page=" & page & (if queryparms=null then "" else "&" & queryparms),
        Source = Json.Document(Web.Contents(url)),
        //world bank api returns a list with two objects (records for powerquery)
        //first record contains meta data including page numer and total number of pages
        //second record contains the actual data
        //meta data and data are combined in one record to simplify logic downstream
        wbmeta = Source{0},
        datarecord = Record.AddField(wbmeta,"data", Source{1})
    in
        datarecord;
 

GetWorldBankData = (query as text, optional queryparms as text) => 
    let
        // call GetWorldBankPage for page 1, returns data pulus meta data containg total number of pages
        // loop all pages, incrementing page number and calling GetWorldBankPage
        data = List.Generate(
            () => GetWorldBankPage(Number.ToText(1), query, queryparms),
            each [page]<=[pages],
            each GetWorldBankPage(Number.ToText([page]+1), query, queryparms)
        ),
        //transform List of records to Table
        output = Table.FromRecords(data),
        //remove all meta data columns , keep the data column
        #"Removed Other Columns" = Table.SelectColumns(output,{"data"}),
        //transform the data column containing a list of records to table rows
        #"Expanded data" = Table.ExpandListColumn(#"Removed Other Columns", "data")
    in
        #"Expanded data";

GetWorldBankIndicator = (query as text, optional queryparms as text) =>
    let
        Source = GetWorldBankData(query, queryparms),
        #"Expanded data" = Table.ExpandRecordColumn(Source, "data", {"indicator", "country", "countryiso3code", "date", "value", "unit", "obs_status", "decimal"}, {"indicator", "country", "countryiso3code", "date", "value", "unit", "obs_status", "decimal"}),
        #"Filtered Rows" = Table.SelectRows(#"Expanded data", each [value] <> null and [value] <> ""),
        #"Expanded country" = Table.ExpandRecordColumn(#"Filtered Rows", "country", {"id", "value"}, {"country.id", "country.value"}),
        #"Removed Columns" = Table.RemoveColumns(#"Expanded country",{"indicator", "unit", "obs_status", "decimal"}),
        #"Changed Type" = Table.TransformColumnTypes(#"Removed Columns",{{"date", Int64.Type}, {"value", type number}}),
        #"Renamed Columns" = Table.RenameColumns(#"Changed Type",{{"date", "year"}, {"country.value", "country.name"}})
    in
        #"Renamed Columns";

GetWorldBankCountry = () =>
    let
        Source = GetWorldBankData("countries", ""),
        #"Expanded data" = Table.ExpandRecordColumn(Source, "data", {"id", "iso2Code", "name", "region", "adminregion", "incomeLevel", "lendingType", "capitalCity", "longitude", "latitude"}, {"id", "iso2Code", "name", "region", "adminregion", "incomeLevel", "lendingType", "capitalCity", "longitude", "latitude"}),
        #"Expanded region" = Table.ExpandRecordColumn(#"Expanded data", "region", {"id", "iso2code", "value"}, {"region.id", "region.iso2code", "region.value"}),
        #"Expanded adminregion" = Table.ExpandRecordColumn(#"Expanded region", "adminregion", {"id", "iso2code", "value"}, {"adminregion.id", "adminregion.iso2code", "adminregion.value"}),
        #"Expanded incomeLevel" = Table.ExpandRecordColumn(#"Expanded adminregion", "incomeLevel", {"id", "iso2code", "value"}, {"incomeLevel.id", "incomeLevel.iso2code", "incomeLevel.value"}),
        #"Expanded lendingType" = Table.ExpandRecordColumn(#"Expanded incomeLevel", "lendingType", {"id", "iso2code", "value"}, {"lendingType.id", "lendingType.iso2code", "lendingType.value"})
    in
        #"Expanded lendingType";

shared WorldBankConnector.TestConnectionImpl = () =>
    let x="AnonymousConnection"  in x;

//NY.GDP.MKTP.PP.CD     GDP
//SP.POP.TOTL
[DataSource.Kind="WorldBankConnector", Publish="WorldBankConnector.Publish"]
shared WorldBankConnector.Contents = (indicator as text, countries as text, dateRange as text) =>
     let
        objects = #table(
            {"Name",       "Key",        "Data",                           "ItemKind", "ItemName", "IsLeaf"},{
            {indicator,      "Indicator",      GetWorldBankIndicator("countries/" & countries & "/indicators/" & indicator, "date=" & dateRange), "Table",    "Table",    true},
            {"Country",      "Country",      GetWorldBankCountry(), "Table",    "Table",    true} 
            }),
        NavTable = Table.ToNavigationTable(objects, {"Key"}, "Name", "Data", "ItemKind", "ItemName", "IsLeaf")
    in
        NavTable;

// Data Source Kind description
WorldBankConnector = [
    TestConnection = (dataSourcePath) as list => {"WorldBankConnector.TestConnectionImpl"},
    Authentication = [
        // Key = [],
        // UsernamePassword = [],
        // Windows = [],
        Implicit = []
    ]
    //Do NOT supply a label to enable identification of datasource in Power BI dialogue
    //Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
WorldBankConnector.Publish = [
    Beta = true,
    Category = "Other",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = WorldBankConnector.Icons,
    SourceTypeImage = WorldBankConnector.Icons
];

WorldBankConnector.Icons = [
    Icon16 = { Extension.Contents("WorldBankConnector16.png"), Extension.Contents("WorldBankConnector20.png"), Extension.Contents("WorldBankConnector24.png"), Extension.Contents("WorldBankConnector32.png") },
    Icon32 = { Extension.Contents("WorldBankConnector32.png"), Extension.Contents("WorldBankConnector40.png"), Extension.Contents("WorldBankConnector48.png"), Extension.Contents("WorldBankConnector64.png") }
];
