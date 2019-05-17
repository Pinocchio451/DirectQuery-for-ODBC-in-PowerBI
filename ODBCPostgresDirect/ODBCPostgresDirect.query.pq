// Use this file to write queries to test your data connector

//Testing Not developed further because of Visual Studio / PowerBI Architecture mismatch (32 vs 64 bit.)
//https://github.com/Microsoft/DataConnectors/issues/158
let
    Source = ODBCPostgresDirect.Database("Example ODBC Source")
in
    Source