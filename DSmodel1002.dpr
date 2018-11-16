library dsmodel1002;
  {-Model 'Bouncing Ball'. Naar: COSMOS, Reference Manual (preliminary version), Dirk L.
    Kettenis (1988).
    Dit model is in deze vorm niet geschikt om vanuit de Shell
    aangestuurd te worden. }

  { Important note about DLL memory management: ShareMem must be the
  first unit in your library's USES clause AND your project's (select
  Project-View Source) USES clause if your DLL exports any procedures or
  functions that pass strings as parameters or function results. This
  applies to all strings passed to and from your DLL--even those that
  are nested in records and classes. ShareMem is the interface unit to
  the BORLNDMM.DLL shared memory manager, which must be deployed along
  with your DLL. To avoid using BORLNDMM.DLL, pass string information
  using PChar or ShortString parameters. }

{.$define test}

uses
  ShareMem,
  windows, SysUtils, Classes, LargeArrays,
  ExtParU, USpeedProc, uDCfunc, UdsModel, UdsModelS, xyTable, DUtils, uError
  {$ifdef test} ,uAlgRout {$endif};

Const
  cModelID      = 1002;  {-Uniek modelnummer}

  {-Beschrijving van de array met afhankelijke variabelen}
  cNrOfDepVar   = 2;    {-Lengte van de array met afhankelijke variabelen}
  cH            = 1;    {-Hoogte (m)}
  cV            = 2;    {-Snelheid (m/s)}

  {-Aantal keren dat een discontinuiteitsfunctie wordt aangeroepen in de procedure met
    snelheidsvergelijkingen (DerivsProc)}
  nDC = 1;

  {-Beschrijving van de array's met daarin de status van de discontinuiteitsfuncties}
  cDCfunc0 = 0;

  {-Beschrijving van het eerste element van de externe parameter-array (EP[cEP0])}
  cNrXIndepTblsInEP0 = 3;  {-Aantal XIndep-tables in EP[cEP0]}
  cNrXdepTblsInEP0   = 0;    {-Aantal Xdep-tables   in EP[cEP0]}
  {-Nummering van de xIndep-tabellen in EP[cEP0]. De nummers 0&1 zijn gereserveerd}
  cTb_Constants      = 2;

  {-Plaats van domain-boundaries op EP-array; DepVar=1 (Hoogte)}
  cDB_BodemNiveau = 1;

  {-Model specifieke fout-codes}
  cBalOnderBodemNiveau = -10000;

var
  Indx: Integer; {-Door de Boot-procedure moet de waarde van deze index worden ingevuld,
                   zodat de snelheidsprocedure 'weet' waar (op de externe parameter-array)
				   hij zijn gegevens moet zoeken}
  ModelProfile: TModelProfile;
  {$ifdef test }
  lf: Textfile;
  {$endif}

Procedure MyDllProc( Reason: Integer );
begin
  if Reason = DLL_PROCESS_DETACH then begin {-DLL is unloading}
    {-Cleanup code here}
    if ( nDC > 0 ) then
      ModelProfile.Free;
  end;
end;

Procedure DerivsProc( var x: Double; var y, dydx: TLargeRealArray;
                      var EP: TExtParArray; var Direction: TDirection;
                      var Context: Tcontext; var aModelProfile: PModelProfile;
                      var IErr: Integer );
{-Deze procedure verschaft de array met afgeleiden 'dydx',
  gegeven het tijdstip 'x' en
  de toestand die beschreven wordt door de array 'y' en
  de externe condities die beschreven worden door de 'external parameter-array EP'.
  Als er geen fout op is getreden bij de berekening van 'dydx' dan wordt in deze procedure
  de variabele 'IErr' gelijk gemaakt aan de constante 'cNoError'.
  Opmerking: in de array 'y' staan dus de afhankelijke variabelen, terwijl 'x' de
  onafhankelijke variabele is}
var
  g,                   {-Gravity (m^2/s^2)}
  kr,                  {-Coefficient of restitution (0<=kr<= 1)}
  BodemNiveau          {-Bodemniveau (m+Ref.niveau)}
  : Double;
  {$ifdef test }
  ContextStr: String;
  {$endif}
  i: Integer;
  Triggered: Boolean;

Function SetKeyAndParValues( var IErr: Integer ): Boolean;

  Function GetG: Double;
  begin
    with EP[ cEP0 ].xInDep.Items[ cTb_Constants ] do
      Result := GetValue( 1, 1 ); {row, column}
  end;

  Function GetKr: Double;
  begin
    with EP[ cEP0 ].xInDep.Items[ cTb_Constants ] do
      Result := GetValue( 1, 2 ); {row, column}
  end;

  Function GetBodemNiveau: Double;
  begin
    Result := 0;
  end;

begin {-Function SetKeyAndParValues}
  g           := GetG;
  kr          := GetKr;
  BodemNiveau := GetBodemNiveau;
  IErr        := cNoError;
  Result := True;
end; {-Function SetKeyAndParValues}

Function v: Double; {-Snelheid (m/s)}
begin
  Result := y[ cV ];
end;

begin

  {$ifdef test }
    AssignFile( lf, AlgRootDir + 'testDSmodel1002.log' ); Rewrite( lf );
  {$endif}

  {$ifdef test }
  Case Context of
    Algorithme:    ContextStr := 'Algorithme';
    ProfileReset:  ContextStr := 'ProfileReset';
    ProfileNext:   ContextStr := 'ProfileNext';
    Trigger:       ContextStr := 'Trigger';
    UpdateYstart:  ContextStr := 'UpdateYstart';
  end;
  {$endif}

  IErr := cUnknownError;
  for i := 1 to cNrOfDepVar do {-Default speed = 0}
    dydx[ i ] := 0;

  {-Geef de aanroepende procedure een handvat naar het ModelProfiel}
  if ( nDC > 0 ) then
    aModelProfile := @ModelProfile
  else
    aModelProfile := NIL;

  if ( Context = UpdateYstart ) then begin {-Run fase 1}
    IErr := cNoError;
  end else begin {-Run fase 2}

    if not SetKeyAndParValues( IErr ) then
      exit;

    {-Bereken de array met afgeleiden 'dydx'}
    dydx[ cV ] := -g;

    with ModelProfile do begin
      y[ cH ] := DCfunc( DomainBoundary, y[ cH ], LT, BodemNiveau, Context, cDCfunc0, Triggered );
      if Triggered then begin
        {$ifdef test }
        Writeln( lf, 'Context= "' + ContextStr + '"; x, y= ', x:8:3, ' ', y[ cH ]:8:3 );
        {$endif}
        dydx[ cH ] := abs( kr * v );
        y[ cV ]    := dydx[ cH ];
      end else begin
        dydx[ cH ] := v;
        {$ifdef test }
        Writeln( lf, 'Context= "' + ContextStr + '"; x, y= ', x:8:3, ' ', y[ cH ]:8:3 );
        {$endif}
      end;
    end;

  end;

  {$ifdef test } Writeln( lf, 'y[ cH ]    = ' + FloatToStrF( y[ cH ], ffFixed, 5, 8 ) );   {$endif}
  {$ifdef test } Writeln( lf, 'dydx[ cH ] = ' + FloatToStrF( dydx[ cH ], ffFixed, 5, 8 ) );  {$endif}

  {$ifdef test }
  CloseFile( lf );
  {$endif}

end; {-DerivsProc}

Function DefaultBootEP( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Initialiseer de meest elementaire gegevens van het model.}
Begin
  Result := DefaultBootEPFromTextFile( EpDir, BootEpArrayOption, cModelID, cNrOfDepVar, nDC, cNrXIndepTblsInEP0,
                                       cNrXdepTblsInEP0, Indx, EP );
  if ( Result = cNoError ) then;
end;

Function TestBootEP( const EpDir: String; const BootEpArrayOption: TBootEpArrayOption; var EP: TExtParArray ): Integer;
  {-Deze boot-procedure verwerkt alle basisgegevens van het model en leest de Shell-gegevens
    uit een bestand. Na initialisatie met deze boot-procedure is het model dus gereed om
	'te draaien'. Deze procedure kan dus worden gebruikt om het model 'los' van de Shell te
	testen}
Begin
  Result := DefaultBootEP( EpDir, BootEpArrayOption, EP );
  if ( Result <> cNoError ) then
    exit;
  Result := DefaultTestBootEPFromTextFile( EpDir, BootEpArrayOption, cModelID, 0, Indx, EP );
  if ( Result <> cNoError ) then
    exit;
  SetReadyToRun( EP);
end;

Exports DerivsProc       index cModelIndxForTDSmodels, {999}
        DefaultBootEP    index cBoot0, {1}
        TestBootEP       index cBoot1; {2}

begin
  {-Dit zgn. 'DLL-Main-block' wordt uitgevoerd als de DLL voor het eerst in het geheugen wordt
    gezet (Reason = DLL_PROCESS_ATTACH)}
  DLLProc := @MyDllProc;
  Indx := cBootEPArrayVariantIndexUnknown;
  if ( nDC > 0 ) then
    ModelProfile := TModelProfile.Create( nDC );

end.
