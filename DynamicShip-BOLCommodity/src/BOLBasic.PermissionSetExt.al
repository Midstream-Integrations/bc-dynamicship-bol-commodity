permissionsetextension 50230 "MID BOL Basic Ext." extends "D365 BASIC"
{
    Permissions = codeunit "MID BOL Commodity Mgt." = X,
                  tabledata "MID BOL Commodity Setup" = R;
}

permissionset 50230 "MID BOL SETUP"
{
    Assignable = true;
    Caption = 'BOL Commodity Setup (admin)';
    Permissions =
        tabledata "MID BOL Commodity Setup" = RIMD,
        table "MID BOL Commodity Setup" = X,
        page "MID BOL Commodity Setup" = X;
}
