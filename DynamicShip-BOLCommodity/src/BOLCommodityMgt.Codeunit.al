codeunit 50230 "MID BOL Commodity Mgt."
{
    Access = Internal;

    var
        CommodityQty: Dictionary of [Code[20], Decimal];
        CommodityOrder: List of [Code[20]];
        DefaultLineFormatTxt: Label 'Qty: %1 %2 - %4', Locked = true, Comment = '%1=Qty, %2=Item No., %3=Item No. 2, %4=Item Description, %5=Base UoM';
        FreightClassPathTok: Label 'TL.FREIGHTCLASS', Locked = true;
        HazmatClassPathTok: Label 'TL.HAZMAT.CLASS', Locked = true;
        NMFCPathTok: Label 'TL.NMFC', Locked = true;
        MatchedPlates: List of [Text];
        MatchedLevel: Integer;
        DiagnosticTxt: Label '*DBG grpNo=[%1] desc=[%2] dim=%3x%4x%5 items=%6 lines=%7 lvl=%8 plates=[%9]', Comment = 'Temporary diagnostic line, see DiagnosticsEnabled()';

    /// <summary>
    /// Builds the commodity description, NMFC and freight class for one commodity line of the Bill of Lading.
    /// DocumentPlate must already be filtered to the plates of the document being printed.
    /// </summary>
    procedure BuildCommodityLine(var DocumentPlate: Record "IWX LP Header"; CommodityGroup: Record "IWX LP Header"; var CommodityDescription: Text; var NMFC: Text; var FreightClass: Text)
    var
        MatchLevel: Integer;
    begin
        Clear(CommodityQty);
        Clear(CommodityOrder);
        Clear(MatchedPlates);
        MatchedLevel := 0;
        CommodityDescription := '';
        NMFC := '';
        FreightClass := '';
        // Every match level is tried against every plate before the next level is allowed to guess, so a
        // plate that can be identified exactly is never claimed by a looser rule first.
        for MatchLevel := 1 to 5 do begin
            CollectCommodityItems(DocumentPlate, CommodityGroup, MatchLevel, NMFC, FreightClass);
            if CommodityOrder.Count() > 0 then begin
                MatchedLevel := MatchLevel;
                break;
            end;
        end;
        CommodityDescription := BuildDescription();
        if DiagnosticsEnabled() then
            CommodityDescription := DiagnosticLine(CommodityGroup) + NewLine() + CommodityDescription;
    end;

    local procedure CollectCommodityItems(var DocumentPlate: Record "IWX LP Header"; CommodityGroup: Record "IWX LP Header"; MatchLevel: Integer; var NMFC: Text; var FreightClass: Text)
    var
        LPLine: Record "IWX LP Line";
        RunningQty: Decimal;
    begin
        Clear(MatchedPlates);
        if not DocumentPlate.FindSet() then
            exit;
        repeat
            if IsSameCommodity(DocumentPlate, CommodityGroup, DocumentPlate, MatchLevel) then begin
                if not MatchedPlates.Contains(DocumentPlate."No.") then
                    MatchedPlates.Add(DocumentPlate."No.");
                // The NMFC and freight class are held against the license plate as freight options. DSHIP does
                // not always surface them in its own perCommLTL columns, so they are read here and the layout
                // falls back on these. First non-blank wins - a commodity line reports one of each. Freight
                // class is stored under TL.FREIGHTCLASS in some Insight Works templates and under
                // TL.HAZMAT.CLASS in others; both are checked.
                if NMFC = '' then
                    NMFC := GetFreightOption(DocumentPlate.SystemId, NMFCPathTok);
                if FreightClass = '' then
                    FreightClass := GetFreightOption(DocumentPlate.SystemId, FreightClassPathTok);
                if FreightClass = '' then
                    FreightClass := GetFreightOption(DocumentPlate.SystemId, HazmatClassPathTok);

                LPLine.SetRange("License Plate No.", DocumentPlate."No.");
                LPLine.SetRange(Type, LPLine.Type::Item);
                if LPLine.FindSet() then
                    repeat
                        if LPLine."No." <> '' then
                            if CommodityQty.ContainsKey(LPLine."No.") then begin
                                RunningQty := CommodityQty.Get(LPLine."No.") + LPLine.Quantity;
                                CommodityQty.Set(LPLine."No.", RunningQty);
                            end else begin
                                CommodityQty.Add(LPLine."No.", LPLine.Quantity);
                                CommodityOrder.Add(LPLine."No.");
                            end;
                    until LPLine.Next() = 0;
            end;
        until DocumentPlate.Next() = 0;
    end;

    // the format comes from BOL Commodity Setup, so each company decides what a commodity line shows
    local procedure CommodityLineFormat(): Text
    var
        Setup: Record "MID BOL Commodity Setup";
    begin
        if Setup.Get() then
            if Setup."Commodity Line Format" <> '' then
                exit(Setup."Commodity Line Format");
        exit(DefaultLineFormatTxt);
    end;

    local procedure BuildDescription(): Text
    var
        Item: Record Item;
        ItemNo: Code[20];
        Result: Text;
        LineFormat: Text;
    begin
        LineFormat := CommodityLineFormat();
        foreach ItemNo in CommodityOrder do begin
            if not Item.Get(ItemNo) then
                Clear(Item);
            if Result <> '' then
                Result += NewLine();
            Result += StrSubstNo(LineFormat, CommodityQty.Get(ItemNo), ItemNo, Item."No. 2", Item.Description, Item."Base Unit of Measure");
        end;
        exit(Result);
    end;

    /// <summary>
    /// Decides whether a license plate belongs to the commodity line currently being printed. Levels run from
    /// exact to loosest; the caller escalates only when a level claimed nothing anywhere on the document.
    /// </summary>
    local procedure IsSameCommodity(Plate: Record "IWX LP Header"; CommodityGroup: Record "IWX LP Header"; DocumentPlate: Record "IWX LP Header"; MatchLevel: Integer): Boolean
    var
        CommodityText: Text;
    begin
        // 1 - exact. DSHIP groups plates by '<Item No.>, <qty on the plate>', so the commodity description
        //     and the plate's own description state the same fact in two spellings: the group reads
        //     'FINXP9831, 40 (0x0x0)' and the plate reads 'FINXP9831, 40.00'. Normalising both - dropping
        //     the dimension suffix and reformatting every numeric token - makes them comparable, and the
        //     quantity in that key is what separates a 40-count commodity line from a 39-count one.
        //     The '(LxWxH)' in the commodity description belongs to whichever plate DSHIP took as the
        //     group's representative, not to the group - a commodity of three plates prints one triple
        //     while its plates each carry their own - so the dimensions must not gate this match.
        if (CommodityGroup.Description <> '') and
           (NormalizeCommodityKey(Plate.Description) = NormalizeCommodityKey(CommodityGroup.Description))
        then
            exit(true);
        if MatchLevel <= 1 then
            exit(false);

        // 2 - the items on the plate and the items named in the commodity description have to be the same
        //     set. A one-sided test - "the description mentions something this plate carries" - lets any
        //     plate that shares a single item join the group, which reports that plate's whole contents
        //     against every commodity it touches and inflates the quantities on both lines.
        if MatchLevel = 2 then
            exit(PlateItemsMatchDescription(Plate, DocumentPlate, CommodityGroup.Description));

        // 3 and 4 - fall back on the text DSHIP built the commodity from. Level 3 keeps the shipment
        //     dimensions as a guard; level 4 drops it, in case DSHIP ever rounds them for display.
        if MatchLevel in [3, 4] then begin
            if MatchLevel = 3 then
                if not DimensionsAgree(Plate, CommodityGroup) then
                    exit(false);
            CommodityText := GetCommodityText(CommodityGroup.Description);
            if StrLen(CommodityText) < 3 then
                exit(false);
            exit(PlateHoldsCommodity(Plate, CommodityText));
        end;

        // 5 - nothing on the plate identified it. Only safe where the document is a single commodity line,
        //     otherwise the lines of one commodity would be reported against another.
        exit(IsSingleCommodityDocument(DocumentPlate));
    end;

    local procedure DimensionsAgree(Plate: Record "IWX LP Header"; CommodityGroup: Record "IWX LP Header"): Boolean
    var
        Dimensions: List of [Decimal];
    begin
        // No dimensions in the description means there is nothing to disagree with. DSHIP also prints
        // '(0x0x0)' when no shipment dimensions are recorded, which carries no information either.
        if not TryGetDimensions(CommodityGroup.Description, Dimensions) then
            exit(true);
        if (Dimensions.Get(1) = 0) and (Dimensions.Get(2) = 0) and (Dimensions.Get(3) = 0) then
            exit(true);
        exit((Plate."Shipment Length" = Dimensions.Get(1)) and
             (Plate."Shipment Width" = Dimensions.Get(2)) and
             (Plate."Shipment Height" = Dimensions.Get(3)));
    end;

    local procedure PlateItemsMatchDescription(Plate: Record "IWX LP Header"; DocumentPlate: Record "IWX LP Header"; CommodityDescription: Text): Boolean
    var
        LPLine: Record "IWX LP Line";
        PlateItems: List of [Text];
        PlateItemNo: Text;
        UpperDescription: Text;
    begin
        UpperDescription := UpperCase(CommodityDescription);
        if UpperDescription = '' then
            exit(false);
        CollectPlateItems(Plate, PlateItems);
        if PlateItems.Count() = 0 then
            exit(false);

        // Every item on the plate has to be named in the commodity description.
        foreach PlateItemNo in PlateItems do
            if not UpperDescription.Contains(PlateItemNo) then
                exit(false);

        // And every item named in the description that exists anywhere on this document has to be on the
        // plate. Without this second half a plate holding one item of a mixed commodity claims the whole
        // commodity line, and that commodity then prints against both plates with inflated quantities.
        if DocumentPlate.FindSet() then
            repeat
                LPLine.SetRange("License Plate No.", DocumentPlate."No.");
                LPLine.SetRange(Type, LPLine.Type::Item);
                if LPLine.FindSet() then
                    repeat
                        if LPLine."No." <> '' then
                            if UpperDescription.Contains(UpperCase(LPLine."No.")) then
                                if not PlateItems.Contains(UpperCase(LPLine."No.")) then
                                    exit(false);
                    until LPLine.Next() = 0;
            until DocumentPlate.Next() = 0;
        exit(true);
    end;

    local procedure CollectPlateItems(Plate: Record "IWX LP Header"; var PlateItems: List of [Text])
    var
        LPLine: Record "IWX LP Line";
    begin
        Clear(PlateItems);
        LPLine.SetRange("License Plate No.", Plate."No.");
        LPLine.SetRange(Type, LPLine.Type::Item);
        if LPLine.FindSet() then
            repeat
                if LPLine."No." <> '' then
                    if not PlateItems.Contains(UpperCase(LPLine."No.")) then
                        PlateItems.Add(UpperCase(LPLine."No."));
            until LPLine.Next() = 0;
    end;

    local procedure PlateHoldsCommodity(Plate: Record "IWX LP Header"; CommodityText: Text): Boolean
    var
        LineItem: Record Item;
        LPLine: Record "IWX LP Line";
        UpperCommodityText: Text;
    begin
        UpperCommodityText := UpperCase(CommodityText);
        LPLine.SetRange("License Plate No.", Plate."No.");
        LPLine.SetRange(Type, LPLine.Type::Item);
        if LPLine.FindSet() then
            repeat
                // The LP line's own Description is often unrelated to what DSHIP built the commodity text
                // from ('FINBP0617, 10.00' etc.); DSHIP builds it from the packed item's description, so
                // both are checked and either match wins.
                if UpperCase(LPLine.Description).StartsWith(UpperCommodityText) then
                    exit(true);
                if LineItem.Get(LPLine."No.") then
                    if UpperCase(LineItem.Description).StartsWith(UpperCommodityText) then
                        exit(true);
            until LPLine.Next() = 0;
    end;

    local procedure IsSingleCommodityDocument(DocumentPlate: Record "IWX LP Header"): Boolean
    var
        DistinctDescriptions: List of [Text];
    begin
        // DSHIP reports one commodity line per distinct plate description, so counting those tells us
        // whether claiming every plate on the document is safe.
        if not DocumentPlate.FindSet() then
            exit(false);
        repeat
            if not DistinctDescriptions.Contains(UpperCase(DocumentPlate.Description)) then
                DistinctDescriptions.Add(UpperCase(DocumentPlate.Description));
        until DocumentPlate.Next() = 0;
        exit(DistinctDescriptions.Count() = 1);
    end;

    local procedure GetCommodityText(CommodityDescription: Text) Result: Text
    var
        EllipsisTok: Label '…', Locked = true;
        OpenBracketPos: Integer;
    begin
        Result := CommodityDescription.TrimEnd();
        // Drop the trailing '(LxWxH)' DSHIP appends
        if Result.EndsWith(')') then begin
            OpenBracketPos := Result.LastIndexOf('(');
            if OpenBracketPos > 1 then begin
                Result := CopyStr(Result, 1, OpenBracketPos - 1);
                Result := Result.TrimEnd();
            end;
        end;
        // Drop the ellipsis DSHIP adds where it shortened the description - either the single Unicode
        // character or literal dots, depending on DSHIP version
        if Result.EndsWith(EllipsisTok) then
            Result := CopyStr(Result, 1, StrLen(Result) - StrLen(EllipsisTok));
        while (Result <> '') and Result.EndsWith('.') do
            Result := CopyStr(Result, 1, StrLen(Result) - 1);
        Result := Result.TrimEnd();
    end;

    local procedure TryGetDimensions(CommodityDescription: Text; var Dimensions: List of [Decimal]): Boolean
    var
        DimensionParts: List of [Text];
        DimensionValue: Decimal;
        OpenBracketPos: Integer;
        DimensionPart: Text;
        DimensionText: Text;
    begin
        Clear(Dimensions);
        DimensionText := CommodityDescription.TrimEnd();
        if not DimensionText.EndsWith(')') then
            exit(false);
        OpenBracketPos := DimensionText.LastIndexOf('(');
        if OpenBracketPos < 1 then
            exit(false);
        DimensionText := CopyStr(DimensionText, OpenBracketPos + 1, StrLen(DimensionText) - OpenBracketPos - 1);
        DimensionText := LowerCase(DimensionText);
        DimensionParts := DimensionText.Split('x');
        if DimensionParts.Count() <> 3 then
            exit(false);
        foreach DimensionPart in DimensionParts do begin
            DimensionPart := DimensionPart.Trim();
            if not Evaluate(DimensionValue, DimensionPart) then
                exit(false);
            Dimensions.Add(DimensionValue);
        end;
        exit(true);
    end;

    local procedure GetFreightOption(LPSystemId: Guid; FreightPath: Text): Text
    var
        FreightOptions: RecordRef;
        PathRef: FieldRef;
        SourceIdRef: FieldRef;
        SourceTypeRef: FieldRef;
        ValueRef: FieldRef;
    begin
        // Freight options live in the Dynamic Ship: Freight Options app, which is not a dependency of this
        // extension, so its table is reached late-bound. A tenant without that app reports nothing here
        // rather than failing to print. Table 84852 'IW Freight Options', keyed on the plate's SystemId.
        if not TryOpenFreightOptions(FreightOptions) then
            exit('');
        SourceTypeRef := FreightOptions.Field(3); // Source Type - the table the option hangs off
        SourceTypeRef.SetRange(Database::"IWX LP Header");
        SourceIdRef := FreightOptions.Field(4); // Source SystemId - the license plate itself
        SourceIdRef.SetRange(LPSystemId);
        PathRef := FreightOptions.Field(7); // Path - e.g. TL.NMFC
        PathRef.SetRange(FreightPath);
        if not FreightOptions.FindSet() then
            exit('');
        // A path can be held per freight integration, so take the first that carries a value
        repeat
            ValueRef := FreightOptions.Field(9); // Value
            if Format(ValueRef.Value) <> '' then
                exit(Format(ValueRef.Value));
        until FreightOptions.Next() = 0;
        exit('');
    end;

    [TryFunction]
    local procedure TryOpenFreightOptions(var FreightOptions: RecordRef)
    begin
        FreightOptions.Open(FreightOptionsTableNo());
    end;

    local procedure FreightOptionsTableNo(): Integer
    begin
        exit(84852); // IW Freight Options, from the Dynamic Ship: Freight Options app
    end;

    local procedure NewLine(): Text[2]
    var
        Result: Text[2];
    begin
        Result[1] := 13;
        Result[2] := 10;
        exit(Result);
    end;

    /// <summary>
    /// Temporary instrumentation. Set this to false once the commodity grouping key is understood - it
    /// prepends a diagnostic line to every commodity description on the printed Bill of Lading.
    /// </summary>
    local procedure DiagnosticsEnabled(): Boolean
    begin
        exit(false);
    end;

    local procedure DiagnosticLine(CommodityGroup: Record "IWX LP Header"): Text
    var
        PlateNo: Text;
        PlateList: Text;
    begin
        foreach PlateNo in MatchedPlates do begin
            if PlateList <> '' then
                PlateList += ',';
            PlateList += PlateNo;
        end;
        exit(StrSubstNo(DiagnosticTxt,
            CommodityGroup."No.",
            CommodityGroup.Description,
            CommodityGroup."Shipment Length",
            CommodityGroup."Shipment Width",
            CommodityGroup."Shipment Height",
            CommodityGroup."Current Item Count",
            CommodityGroup."Line Count",
            MatchedLevel,
            PlateList));
    end;

    /// <summary>
    /// Reduces a commodity or plate description to a comparable key. The commodity description carries a
    /// trailing '(LxWxH)' that the plate's own description does not, and the two format quantities
    /// differently ('40' against '40.00'), so the suffix is dropped and every numeric token reformatted.
    /// </summary>
    local procedure NormalizeCommodityKey(DescriptionText: Text) Result: Text
    var
        PartValue: Decimal;
        OpenBracketPos: Integer;
        Parts: List of [Text];
        Part: Text;
        Working: Text;
    begin
        Working := DescriptionText.Trim();
        if Working.EndsWith(')') then begin
            OpenBracketPos := Working.LastIndexOf('(');
            if OpenBracketPos > 1 then begin
                Working := CopyStr(Working, 1, OpenBracketPos - 1);
                Working := Working.Trim();
            end;
        end;
        // The commodity description separates items with ' / ' where the plate's own description uses
        // '; ', so both are folded onto one separator before the parts are compared.
        Working := Working.Replace(';', ',');
        Working := Working.Replace('/', ',');
        Parts := Working.Split(',');
        foreach Part in Parts do begin
            Part := Part.Trim();
            if Part <> '' then begin
                if Evaluate(PartValue, Part) then
                    Part := Format(PartValue, 0, 9)
                else
                    Part := UpperCase(Part);
                if Result <> '' then
                    Result += ',';
                Result += Part;
            end;
        end;
    end;
}
