// This file contains your Data Connector logic
section ODBCDirect;

/* This is the method for connection to ODBC*/
[DataSource.Kind="ODBCDirect", Publish="ODBCDirect.Publish"]
shared ODBCDirect.Database = (dsn as text) as table =>
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
        //
        // Call to Odbc.DataSource
        //
        OdbcDatasource = Odbc.DataSource(ConnectionString, [
            HierarchicalNavigation = true,
            TolerateConcatOverflow = true,
            // These values should be set by previous steps
            CredentialConnectionString = CredentialConnectionString,
            SqlCapabilities = [
                SupportsTop = true,
                Sql92Conformance = 8,
                SupportsNumericLiterals = true,
                SupportsStringLiterals = true,
                SupportsOdbcDateLiterals = true,
                SupportsOdbcTimeLiterals = true,
                SupportsOdbcTimestampLiterals = true
            ],
            SQLGetFunctions = [
                // Disable using parameters in the queries that get generated.
                // We enable numeric and string literals which should enable literals for all constants.
                SQL_API_SQLBINDPARAMETER = false
            ]
        ])
        
    in OdbcDatasource;


// Data Source Kind description
ODBCDirect = [
 // Test Connection
    TestConnection = (dataSourcePath) => 
        let
            json = Json.Document(dataSourcePath),
            dsn = json[dsn]
        in
            { "ODBCDirect.Database", dsn}, 
 // Authentication Type
    Authentication = [
        UsernamePassword = [],
        Implicit = []
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

// Data Source UI publishing description
ODBCDirect.Publish = [
    Category = "Database",
    ButtonText = { Extension.LoadString("ButtonTitle"), Extension.LoadString("ButtonHelp") },
    LearnMoreUrl = "https://powerbi.microsoft.com/",
    SourceImage = ODBCDirect.Icons,
    SourceTypeImage = ODBCDirect.Icons,
    // This is for Direct Query Support
    SupportsDirectQuery = true
];

ODBCDirect.Icons = [
    Icon16 = { Extension.Contents("ODBCDirect16.png"), Extension.Contents("ODBCDirect20.png"), Extension.Contents("ODBCDirect24.png"), Extension.Contents("ODBCDirect32.png") },
    Icon32 = { Extension.Contents("ODBCDirect32.png"), Extension.Contents("ODBCDirect40.png"), Extension.Contents("ODBCDirect48.png"), Extension.Contents("ODBCDirect64.png") }
];

