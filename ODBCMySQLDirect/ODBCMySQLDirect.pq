// This file contains your Data Connector logic
section ODBCMySQLDirect;

// When set to true, additional trace information will be written out to the User log. 
// This should be set to false before release. Tracing is done through a call to 
// Diagnostics.LogValue(). When EnableTraceOutput is set to false, the call becomes a 
// no-op and simply returns the original value.
EnableTraceOutput = true;

Config_DriverName = "MySQL ODBC 8.0 Unicode (x64)";
Config_SqlConformance = 8;  // (SQL_SC) null, 1, 2, 4, 8
Config_GroupByCapabilities = 2; // (SQL_GB) 0, 1, 2, 3, 4
Config_FractionalSecondsScale = 3; //set
Config_SupportsTop = false; // true, false
Config_DefaultUsernamePasswordHandling = true;  // true, false
Config_UseParameterBindings = false;  // true, false, null
Config_StringLiterateEscapeCharacters  = { "\" }; // ex. { "\" }
Config_UseCastInsteadOfConvert = true; // true, false, null
Config_SQ_Predicates = 0x0000FFFF; // (SQL_SP) all
Config_SQL_AF = 0xFF; //all
Config_EnableDirectQuery = true;    // true, false



/* This is the method for connection to ODBC*/
[DataSource.Kind="ODBCMySQLDirect", Publish="ODBCMySQLDirect.UI"]
shared ODBCMySQLDirect.Database = (dsn as text) as table =>
      let
        //
        // Connection string settings
        //
        ConnectionString = [
            DSN=dsn
        ],

        //
        // Handle credentials
        // Credentials are not persisted with the query and are set through a separate 
        // record field - CredentialConnectionString. The base Odbc.DataSource function
        // will handle UsernamePassword authentication automatically, but it is explictly
        // handled here as an example. 
        //
        Credential = Extension.CurrentCredential(),
        encryptionEnabled = Credential[EncryptConnection]? = true,
		CredentialConnectionString = [
            SSLMode = if encryptionEnabled then "verify-full" else "require",
            UID = Credential[Username],
            PWD = Credential[Password],
            BoolsAsChar = 0,
            MaxVarchar = 65535
        ],
        defaultConfig = BuildOdbcConfig(),
    
        SqlCapabilities = defaultConfig[SqlCapabilities] & [
        //add additional non-configuration handled overrides here
        GroupByCapabilities = 2
        ],
        SQLGetInfo = defaultConfig[SQLGetInfo] & [
        //add additional non-configuration handled overrides here
        SQL_AGGREGATE_FUNCTIONS = 0xFF
        ],
        SQLGetFunctions = defaultConfig[SQLGetFunctions] & [
        //add additional non-configuration handled overrides here
        ],

        // Build AstVisitor
        // This record allows you to customize the generated SQL for certain
        // operations. The most common usage is to define syntax for LIMIT/OFFSET operators 
        // when TOP is not supported. 
        // 
        AstVisitor = [
            // Fix for Offset / Limit
            LimitClause = (skip, take) =>
            let
                limit = Text.Format("LIMIT "),
                offset = if (skip <> null and skip > 0) then Text.Format("#{0},", {skip}) else "",
                rows = if (take <> null) then Text.Format("#{0}", {take}) else ""
            in
                [
                Text = Text.Format("#{0} #{1} #{2}", {limit, offset, rows}),
                Location = "AfterQuerySpecification"
                ],
            // Fix for Type Casts
            Constant =
                    let
                        Quote = each Text.Format("'#{0}'", { _ }),
                        Cast = (value, typeName) => [
                            Text = Text.Format("CAST(#{0} as #{1})", { value, typeName })
                        ],
                        Visitor = [
                            // This is to work around parameters being converted to VARCHAR
                            // and to work around driver crash when using TYPE_TIME parameters.
                            NUMERIC = each Cast(_, "NUMERIC"),
                            DECIMAL = each Cast(_, "DECIMAL"),
                            INTEGER = each Cast(_, "INTEGER"),
                            FLOAT = each Cast(_, "FLOAT"),
                            REAL = each Cast(_, "REAL"),
                            DOUBLE = each Cast(_, "DOUBLE"),
                            DATE = each Cast(Quote(Date.ToText(_, "yyyy-MM-dd")), "DATE"),
                            TEXT = each Cast(_, "WLONGVARCHAR"),
                            TIMESTAMPTZ = each Cast(Quote(DateTime.ToText(_, "yyyy-MM-dd HH:mm:ss.sssssss")), "TIMESTAMP"),
                            TIMETZ = each Cast(Quote(Time.ToText(_, "HH:mm:ss.sssssss")), "TIME"),
                            UUID = each Cast(_, "GUID")
                        ]
                    in
                        (typeInfo, ast) => Record.FieldOrDefault(Visitor, typeInfo[TYPE_NAME], each null)(ast[Value])
            ],

             // SQLGetTypeInfo can be specified in two ways:
            // 1. A #table() value that returns the same type information as an ODBC
            //    call to SQLGetTypeInfo.
            // 2. A function that accepts a table argument, and returns a table. The 
            //    argument will contain the original results of the ODBC call to SQLGetTypeInfo.
            //    Your function implementation can modify/add to this table.
            //
            // For details of the format of the types table parameter and expected return value,
            // please see: https://docs.microsoft.com/en-us/sql/odbc/reference/syntax/sqlgettypeinfo-function
            //
            // The sample implementation provided here will simply output the original table
            // to the user trace log, without any modification. 
            
            SQLGetTypeInfo = (types) => 
                if (EnableTraceOutput <> true) then types else
                let
                    // Outputting the entire table might be too large, and result in the value being truncated.
                    // We can output a row at a time instead with Table.TransformRows()
                    rows = Table.TransformRows(types, each Diagnostics.LogValue("SQLGetTypeInfo " & _[TYPE_NAME], _)),
                    toTable = Table.FromRecords(rows)
                in
                    Value.ReplaceType(toTable, Value.Type(types)),         

            // This is to work around the driver returning the deprecated
            // TIMESTAMP, DATE and TIME instead of TYPE_TIMESTAMP, TYPE_DATE and TYPE_TIME
            // for column metadata returned by SQLColumns. The column types also don't
            // match the types that are returned by SQLGetTypeInfo.
            
            SQLColumns = (catalogName, schemaName, tableName, columnName, source) =>
                let
                    OdbcSqlType.DATETIME = 9,
                    OdbcSqlType.TYPE_DATE = 91,
                    OdbcSqlType.TIME = 10,
                    OdbcSqlType.TYPE_TIME = 92,
                    OdbcSqlType.TIMESTAMP = 11,
                    OdbcSqlType.TYPE_TIMESTAMP = 93,
                    OdbcSqlType.VARCHAR = 12,
                    OdbcSqlType.TEXT = -10,

                    FixDataType = (dataType) =>
                        if dataType = OdbcSqlType.VARCHAR then
                            OdbcSqlType.TEXT
                        else if dataType = OdbcSqlType.DATETIME then
                            OdbcSqlType.TYPE_DATE
                        else if dataType = OdbcSqlType.TIME then
                            OdbcSqlType.TYPE_TIME
                        else if dataType = OdbcSqlType.TIMESTAMP then
                            OdbcSqlType.TYPE_TIMESTAMP
                        else
                            dataType,
                    Transform = Table.TransformColumns(source, { { "DATA_TYPE", FixDataType } })
                in
                    if (EnableTraceOutput <> true) then Transform else
                    // the if statement conditions will force the values to evaluated/written to diagnostics
                    if (Diagnostics.LogValue("SQLColumns.TableName", tableName) <> "***" and Diagnostics.LogValue("SQLColumns.ColumnName", columnName) <> "***") then
                        let
                            // Outputting the entire table might be too large, and result in the value being truncated.
                            // We can output a row at a time instead with Table.TransformRows()
                            rows = Table.TransformRows(Transform, each Diagnostics.LogValue("SQLColumns", _)),
                            toTable = Table.FromRecords(rows)
                        in
                            Value.ReplaceType(toTable, Value.Type(Transform))
                    else
                        Transform,

        //
        // Call to Odbc.DataSource
        //
        OdbcDatasource = Odbc.DataSource(ConnectionString, [

            // Enables client side connection pooling for the ODBC driver.
            // Most drivers will want to set this value to true.
            ClientConnectionPooling = true,
            // When HierarchialNavigation is set to true, the navigation tree
            // will be organized by Database -> Schema -> Table. When set to false,
            // all tables will be displayed in a flat list using fully qualified names. 
            HierarchicalNavigation = true,
            //Prevent exposure of Native Query
            HideNativeQuery = true,
            //Allows the M engine to select a compatible data type when conversion between two specific numeric types is not declared as supported in the SQL_CONVERT_* capabilities.
            SoftNumbers = true,
            TolerateConcatOverflow = true,
            // These values should be set by previous steps
            CredentialConnectionString = CredentialConnectionString,
            //Requires AstVisitor since Top is not supported in Postgres
            AstVisitor = AstVisitor,
            SqlCapabilities = SqlCapabilities,
            SQLGetInfo = SQLGetInfo,
            SQLGetTypeInfo = SQLGetTypeInfo,
            SQLColumns = SQLColumns
        ])
        
    in OdbcDatasource;


// Data Source Kind description
ODBCMySQLDirect = [
 // Test Connection
    TestConnection = (dataSourcePath) => 
        let
            json = Json.Document(dataSourcePath),
            dsn = json[dsn]
        in
            { "ODBCMySQLDirect.Database", dsn}, 
 // Authentication Type
    Authentication = [
        UsernamePassword = [],
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
ODBCMySQLDirect.UI = [
    Category = "Database",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = ODBCMySQLDirect.Icons,
    SourceTypeImage = ODBCMySQLDirect.Icons,
    // This is for Direct Query Support
    SupportsDirectQuery = true
];

ODBCMySQLDirect.Icons = [
    Icon16 = { Extension.Contents("ODBCMySQLDirect16.png"), Extension.Contents("ODBCMySQLDirect20.png"), Extension.Contents("ODBCMySQLDirect24.png"), Extension.Contents("ODBCMySQLDirect32.png") },
    Icon32 = { Extension.Contents("ODBCMySQLDirect32.png"), Extension.Contents("ODBCMySQLDirect40.png"), Extension.Contents("ODBCMySQLDirect48.png"), Extension.Contents("ODBCMySQLDirect64.png") }
];

// build settings based on configuration variables
BuildOdbcConfig = () as record =>
    let        
        defaultConfig = [
            SqlCapabilities = [],
            SQLGetFunctions = [],
            SQLGetInfo = []
        ],

        withParams =
            if (Config_UseParameterBindings = false) then
                let 
                    caps = defaultConfig[SqlCapabilities] & [ 
                        SqlCapabilities = [
                            SupportsNumericLiterals = true,
                            SupportsStringLiterals = true,                
                            SupportsOdbcDateLiterals = true,
                            SupportsOdbcTimeLiterals = true,
                            SupportsOdbcTimestampLiterals = true
                        ]
                    ],
                    funcs = defaultConfig[SQLGetFunctions] & [
                        SQLGetFunctions = [
                            SQL_API_SQLBINDPARAMETER = false,
                            SQL_CONVERT_FUNCTIONS = 0x2
                        ]
                    ]
                in
                    defaultConfig & caps & funcs
            else
                defaultConfig,
                
        withEscape = 
            if (Config_StringLiterateEscapeCharacters <> null) then 
                let
                    caps = withParams[SqlCapabilities] & [ 
                        SqlCapabilities = [
                            StringLiteralEscapeCharacters = Config_StringLiterateEscapeCharacters
                        ]
                    ]
                in
                    withParams & caps
            else
                withParams,

        withTop =
            let
                caps = withEscape[SqlCapabilities] & [ 
                    SqlCapabilities = [
                        SupportsTop = Config_SupportsTop
                    ]
                ]
            in
                withEscape & caps,

        withGroup =
            let
                caps = withEscape[SqlCapabilities] & [ 
                    SqlCapabilities = [
                        GroupByCapabilities = Config_GroupByCapabilities
                    ]
                ]
            in
                withTop & caps,

        withCastOrConvert = 
            if (Config_UseCastInsteadOfConvert = true) then
                let
                    caps = withGroup[SQLGetFunctions] & [ 
                        SQLGetFunctions = [
                            SQL_CONVERT_FUNCTIONS = 0x2 /* SQL_FN_CVT_CAST */
                        ]
                    ]
                in
                    withGroup & caps
            else
                withGroup,

        withSeconds = 
            if (Config_FractionalSecondsScale <> null) then 
                let
                    caps = withCastOrConvert[SqlCapabilities] & [ 
                        SqlCapabilities = [
                            FractionalSecondsScale = Config_FractionalSecondsScale
                        ]
                    ]
                in
                    withCastOrConvert & caps
            else
                withCastOrConvert,

        withPredicates =
            if (Config_SQ_Predicates <> null) then
                let
                    caps = withSeconds[SQLGetInfo] & [
                        SQLGetInfo = [
                            SQL_SQL92_PREDICATES = Config_SQ_Predicates
                        ]
                    ]
                in
                    withSeconds & caps
            else
                withSeconds,

        withAggregates = 
            if (Config_SQL_AF <> null) then
                let
                    caps = withPredicates[SQLGetInfo] & [
                        SQLGetInfo = [
                            SQL_AGGREGATE_FUNCTIONS = Config_SQL_AF
                        ]
                    ]
                in
                    withPredicates & caps
            else
                withPredicates,

        withSqlConformance =
            if (Config_SqlConformance <> null) then
                let
                    caps = withAggregates[SQLGetInfo] & [
                        SQLGetInfo = [
                            SQL_SQL_CONFORMANCE = Config_SqlConformance
                        ]
                    ]
                in
                    withAggregates & caps
            else
                withAggregates
    in
        withSqlConformance;

// 
// Load common library functions
// 
Extension.LoadFunction = (name as text) =>
    let
        binary = Extension.Contents(name),
        asText = Text.FromBinary(binary)
    in
        Expression.Evaluate(asText, #shared);

// Diagnostics module contains multiple functions. We can take the ones we need.
Diagnostics = Extension.LoadFunction("Diagnostics.pqm");
Diagnostics.LogValue = if (EnableTraceOutput) then Diagnostics[LogValue] else (prefix, value) => value;

// OdbcConstants contains numeric constants from the ODBC header files, and a 
// helper function to create bitfield values.
ODBC = Extension.LoadFunction("OdbcConstants.pqm");
Odbc.Flags = ODBC[Flags];