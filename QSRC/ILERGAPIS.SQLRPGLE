**free
//--------------------------------------------------------------------
// >>PRE-COMPILER<<
//
//   >>TASK 199395<<
//
//   >>CRTCMD<< CRTSQLRPGI   OBJ(&LI/&OB) +
//                           SRCFILE(&SL/&SF) +
//                           SRCMBR(&SM) +
//                           OBJTYPE(*MODULE) +
//                           OPTION(*EVENTF) +
//                           RPGPPOPT(*LVL2);
//
//   >>EXECUTE<<
//
//   >>CMD<<    UPDSRVPGM    SRVPGM(&LI/&OB) +
//                           MODULE(&LI/&OB);
//
// >>END-PRE-COMPILER<<
//--------------------------------------------------------------------
//     Object ID: CELSGAPIS
//   Description: Service Program for using Google APIs
//        Author: Donald Leong
//          Date: 21 SEP 2017
//--------------------------------------------------------------------
// Some required readings:
//========================
// https://developers.google.com/url-shortener/v1/getting_started
// https://www.ibm.com/developerworks/ibmi/library/i-incorporating-web-service/index.html
// https://www.ibm.com/developerworks/data/library/techarticle/dm-1306nosqlforjson1/index.html
// https://www.mcpressonline.com/analytics-cognitive/db2/
//         techtip-store-and-parse-json-data-natively-with-db2-for-i
// https://www.ibm.com/developerworks/ibmi/library/i-json-store-technology/index.html?ca=drs-
// https://www.mcpressonline.com/programming-other/general/
//         techtip-json-and-xml-conversion-in-db2-for-i
// http://ibmsystemsmag.com/blogs/i-can/january-2017/json_table-function/
// http://dev.bitly.com/transition_from_google.html
//--------------------------------------------------------------------
// Modifications:
//--------------------------------------------------------------------
// Mod#  |   Date     | Programmer   |   Description
//--------------------------------------------------------------------
// 162534  09/21/2017      DL         Initial release
//
// 198434  03/27/2018      EWH        Change getGoogleShort checksql to ignore
// (S8434)                            error -4302 for Java stored procedure exception.
//
// 199395  04/02/2018      DL         Switch shorten/expand url from Google to
//                                    Bitly due to google service deprecation
//--------------------------------------------------------------------

  ctl-opt copyright('Cels Enterprises Inc. 2017')
    nomain
    debug option(*NODEBUGIO : *SRCSTMT : *NOUNREF : *NOSHOWCPY)
    bnddir('CELSBNDDIR':'QC2LE');

/copy CECOPYSRC,CELSDSPECS

  dcl-ds dsGeoCode      qualified template;
    sLatitude           varchar(50);
    sLongitude          varchar(50);
  end-ds;

  dcl-ds dsAddress      qualified template;
    sPlace              varchar(50);
    sAddr1              varchar(50);
    sAddr2              varchar(50);
    sCity               varchar(50);
    sState              varchar(20);
    sZip                varchar(5);
    sCountry            varchar(30);
  end-ds;

// For Google Map API
// Account: USERID = celsmisdept@gmail.com, PASWRD = 10****J**
  dcl-s sMapKey         varchar(500) inz('key=your_key');
  dcl-s sMapUrl         varchar(500) inz('https://maps.googleapis.com/maps/api/');

// For Google URL Shorten API
// Account: USERID = celsmisdept@gmail.com, PASWRD = 10****J**
  dcl-s sMiniKey        varchar(500) inz('key=your_key');
  dcl-s sMiniUrl        varchar(500) inz('https://www.googleapis.com/urlshortener/v1/url');

// For Bitly URL Shorten API
// Account: USERID = celsmisdept@gmail.com, PASWRD = 10****J**
  dcl-s sBitUrl         varchar(100) inz('https://api-ssl.bitly.com/v3');
  dcl-s sBitToken       varchar(500) inz('your_token');

  // 199395 **** dcl-c cSQL_Java_Proc_Err           -7008;      // S8434
  dcl-c cSQL_Java_Proc_Err           -4302;      // 199395
  dcl-c cSQL_Java_Proc_Err           -7008;


//-------------------------------------------------------------
// Get GeoCode from Google Map API
//-------------------------------------------------------------

 dcl-proc getGeoCode    export;
   dcl-pi *n            ind;
     sVenueIn           like(dsAddress.sPlace)   const;
     sAddr1In           like(dsAddress.sAddr1)   const options(*omit);
     sAddr2In           like(dsAddress.sAddr2)   const options(*omit);
     sCityIn            like(dsAddress.sCity)    const options(*omit);
     sStateIn           like(dsAddress.sState)   const options(*omit);
     sZipIn             like(dsAddress.sZip)     const options(*omit);
     sCountryIn         like(dsAddress.sCountry) const options(*omit);
     sGeoLat            like(dsGeoCode.sLatitude);
     sGeoLng            like(dsGeoCode.sLongitude);
   end-pi;

   dcl-s  sUrl          varchar(1024);
   dcl-s  sAddress      varchar(1024);
   dcl-ds dsAddr        likeds(dsAddress);

// Add jvm environment
   addJvmEnvVar();

   dsAddr.sPlace = sVenueIn;

   if %parms >= %parmnum(sAddr1In) and %addr(sAddr1In) <> *null;
     dsAddr.sAddr1 = sAddr1In;
   endif;

   if %parms >= %parmnum(sAddr2In) and %addr(sAddr2In) <> *null;
     dsAddr.sAddr2 = sAddr2In;
   endif;

   if %parms >= %parmnum(sCityIn) and %addr(sCityIn) <> *null;
     dsAddr.sCity = sCityIn;
   endif;

   if %parms >= %parmnum(sStateIn) and %addr(sStateIn) <> *null;
     dsAddr.sState = sStateIn;
   endif;

   if %parms >= %parmnum(sZipIn) and %addr(sZipIn) <> *null;
     dsAddr.sZip = sStateIn;
   endif;

   if %parms >= %parmnum(sCountryIn) and %addr(sCountryIn) <> *null;
     dsAddr.sCountry = sCountryIn;
   endif;

   sAddress = dsAddr.sPlace + ' ' +
              dsAddr.sAddr1 + ' ' +
              dsAddr.sAddr2 + ' ' +
              dsAddr.sCity  + ' ' +
              dsAddr.sState + ' ' +
              dsAddr.sZip;

   if dsAddr.sCountry <> '';
     sAddress += ' '+dsAddr.sCountry;
   endif;

   if sAddress <> '';

// Reach out to GOOGLE to get data
     exec sql
       select *
         into :sGeoLat, :sGeoLng
         from xmltable('$doc/GeocodeResponse/result/geometry/location'
              passing
              xmlparse(document systools.httpgetclob(
                      (:sMapUrl
                       ||'geocode/xml?address='
                       ||systools.urlencode(:sAddress,'UTF-8')
                       ||'&'
                       ||:sMapKey),
              '')) as "doc"
              columns
                geolat varchar(50) path './lat',
                geolng varchar(50) path './lng'
              ) as WebServiceResult
       fetch first 1 row only;
     checksql(SQLCODE);

   endif;

   return (sGeoLat <> '' and sGeoLng <> '');
 end-proc;

//-------------------------------------------------------------
// Get Place Name using Geo Code via Google API
//-------------------------------------------------------------

 dcl-proc getPlaceName  export;
   dcl-pi *n            varchar(1024);
     sLatitude          like(dsGeoCode.sLatitude)  const;
     sLongitude         like(dsGeoCode.sLongitude) const;
   end-pi;

   dcl-s  sUrl          varchar(1024);
   dcl-s  sGeoCodes     varchar(100);
   dcl-s  sLat          like(dsGeoCode.sLatitude);
   dcl-s  sLng          like(dsGeoCode.sLongitude);
   dcl-s  sRecValu      varchar(200);
   dcl-s  sRecType      varchar(200);
   dcl-ds dsAddr        likeds(dsAddress);

// Add jvm environment
   addJvmEnvVar();

   if sLatitude <> '' and sLongitude <> '';
     sGeoCodes = sLatitude+','+sLongitude;

// Reach out to GOOGLE to get data using XML
// "type" has 2 data elements - need only the first one hence type[1]
     exec sql
       declare curResult cursor for
         select *
           from xmltable('$doc/GeocodeResponse/result/address_component'
                passing
                xmlparse(document systools.httpgetclob(
                        (:sMapUrl
                         ||'geocode/xml?latlng='
                         ||systools.urlencode(:sGeoCodes,'UTF-8')
                         ||'&'
                         ||:sMapKey),
                '')) as "doc"
                columns
                  recvalu varchar(50) path './short_name',
                  rectype varchar(50) path './type[1]'
                ) as WebServiceResult;
     checksql(SQLCODE);

     exec sql
       open curResult;
     checksql(SQLCODE);

// Spin thru result set to get address
     exec sql
       fetch from curResult into :sRecValu, :sRecType;
     dow checksql(SQLCODE) = cSQL_OK;
       select;
         when sRecType = 'premise' and dsAddr.sPlace = '';
           dsAddr.sPlace = sRecValu;
         when sRecType = 'street_number' and dsAddr.sAddr1 = '';
           dsAddr.sAddr1 = sRecValu;
         when sRecType = 'route' and dsAddr.sAddr2 = '';
           dsAddr.sAddr2 = sRecValu;
         when sRecType = 'locality' and dsAddr.sCity = '';
           dsAddr.sCity = sRecValu;
         when sRecType = 'administrative_area_level_1' and dsAddr.sState = '';
           dsAddr.sState = sRecValu;
         when sRecType = 'postal_code' and dsAddr.sZip = '';
           dsAddr.sZip = sRecValu;
         when sRecType = 'country' and dsAddr.sCountry = '';
           dsAddr.sCountry = sRecValu;
       endsl;
       exec sql
         fetch from curResult into :sRecValu, :sRecType;
     enddo;

     exec sql
       close curResult;
     checksql(SQLCODE);

   endif;

   return dsAddr;
 end-proc;

//-------------------------------------------------------------
// Get a URL representing a static map from Google
// Default values:
//    zoom = 12
//    size = 400 x 400
//    marker color = red
//    marker label = 'S'
//-------------------------------------------------------------

 dcl-proc getStaticMapUrl export;
   dcl-pi *n            varchar(1024);
     sLatitude          like(dsGeoCode.sLatitude)  const;
     sLongitude         like(dsGeoCode.sLongitude) const;
     nZoomNum           int(5)      const options(*omit:*nopass);
     sPicSize           varchar(10) const options(*omit:*nopass);
     sMarkerColor       varchar(10) const options(*omit:*nopass);
     sMarkerLabel       varchar(5)  const options(*omit:*nopass);
   end-pi;

   dcl-s sTmpUrl        varchar(1024);
   dcl-s sUrl           varchar(1024);
   dcl-s sZoom          varchar(5)  inz('12');
   dcl-s sSize          varchar(10) inz('400x400');
   dcl-s sColor         varchar(10) inz('red');
   dcl-s sLabel         varchar(5)  inz('S');

// Add jvm environment
   addJvmEnvVar();

   if %parms >= %parmnum(nZoomNum) and %addr(nZoomNum) <> *null
      and nZoomNum > 0;
     sZoom = %char(nZoomNum);
   endif;

   if %parms >= %parmnum(sPicSize) and %addr(sPicSize) <> *null
      and sPicSize <> '';
     sSize = sPicSize;
   endif;

   if %parms >= %parmnum(sMarkerColor) and %addr(sMarkerColor) <> *null
      and sMarkerColor <> '';
     sColor = sMarkerColor;
   endif;

   if %parms >= %parmnum(sMarkerLabel) and %addr(sMarkerLabel) <> *null
      and sMarkerLabel <> '';
     sLabel = sMarkerLabel;
   endif;

// Assemble the URL
   sTmpUrl = sMapUrl+
             'staticmap?center='+sLatitude+','+sLongitude+
             '&size='+sSize+
             '&zoom='+sZoom+
             '&markers=color:'+sColor+'|label:'+sLabel+
             '|'+sLatitude+','+sLongitude+
             '&'+sMapKey;

// Encode the URL
   exec sql
     values systools.urlencode(:sTmpUrl,'UTF-8')
       into :sUrl;
   checksql(SQLCODE);

   return sUrl;
 end-proc;

//-------------------------------------------------------------
// Get a URL representing a shortened version of a URL
// Shortening service provider is Google
// ============================================================
// Google Shorten URL deprecated on 4/13/18
// Service moved over to Bitly account.
// Bitly requires to use httpgetclob instead of httppostclob
//-------------------------------------------------------------

 dcl-proc getGoogleShort export;
   dcl-pi *n             varchar(80);
     sLongUrl            varchar(1024) const;
   end-pi;

   dcl-s sPayload       varchar(1024);
   dcl-s sReqUrl        varchar(1024);
   dcl-s sHeader        varchar(1024);
   dcl-s sShortUrl      varchar(80);


// Add jvm environment
   addJvmEnvVar();

// Construct request header
   sHeader = '<httpHeader>'+
             '<header name="Content-Type" value="application/json"/>'+
             '</httpHeader>';

// Assemble the request URL
   sReqUrl = sMiniUrl+'?'+sMiniKey;

// Assemble payload
   sPayload = '{"longUrl":"'+sLongUrl+'"}';

// Reach out to GOOGLE to get data using JSON
// Data parsing with internal JSON conversion
   exec sql
     select *
       into :sShortUrl
       from json_table(
              systools.httppostclob(
                :sReqUrl,
                cast(:sHeader as clob(1k)),
                cast(:sPayload as clob(200k))
              ), '$'
              columns (
                id varchar(80) path '$.id'
             )) as x;

  // Ignore Java stored procedure or user-defined function exception
   // S8434 ***** checksql(SQLCODE);
   CheckSql(SQLCODE:*omit:*omit:*omit:*omit:cSQL_Java_Proc_Err); // S8434

   return sShortUrl;
 end-proc;

//-------------------------------------------------------------
// Expand a shortened URL back to regular URL
// Shortening service provider is Google
//-------------------------------------------------------------

 dcl-proc getGoogleLong export;
   dcl-pi *n            varchar(1024);
     sShortUrl          varchar(80) const;
   end-pi;

   dcl-s sLongUrl       varchar(1024);

// Add jvm environment
   addJvmEnvVar();

// Reach out to GOOGLE to get data using JSON
// Data parsing with internal JSON conversion
   exec sql
     select *
       into :sLongUrl
       from json_table(
              systools.httpgetclob(
                (:sMiniUrl
                 ||'?shortUrl='
                 ||systools.urlencode(:sShortUrl,'UTF-8')
                 ||'&projection=FULL'
                 ||'&fields=longUrl'
                 ||'&'
                 ||:sMiniKey),
                null
              ), '$'
              columns (
                id varchar(1024) path '$.longUrl'
             )) as x;
   checksql(SQLCODE);

   return sLongUrl;
 end-proc;

//-------------------------------------------------------------
// Add JVM environment variable so that all the UDF and UDTF
// will work
//-------------------------------------------------------------

 dcl-proc addJvmEnvVar  export;

   dcl-s sCmd           varchar(100);

   sCmd = 'CHGENVVAR ENVVAR(JAVA_HOME)'+
          ' VALUE('+enquote('/QOpenSys/QIBM/ProdData/JavaVM/jdk70/64bit')+')'+
          ' LEVEL(*JOB)';

   system(sCmd);
 end-proc;

//-------------------------------------------------------------
// Get a URL representing a shortened version of a URL
// Shortening service provider is Bitly
//-------------------------------------------------------------

 dcl-proc getBitlyShort export;
   dcl-pi *n            varchar(80);
     sLongUrl           varchar(1024) const;
   end-pi;

   dcl-s sPayLoad       varchar(1024);
   dcl-s sReqUrl        varchar(1024);
   dcl-s sHeader        varchar(1024);
   dcl-s sShortUrl      varchar(80);

// Add jvm environment
   addJvmEnvVar();

// Construct request header
   sHeader = '<httpHeader>'+
             '<header name="Content-Type" value="application/json"/>'+
             '</httpHeader>';

// Assemble the request URL
   sReqUrl = %trim(sBitUrl)+'/shorten'+'?access_token='+%trim(sBitToken);
   sPayLoad = sLongUrl;

// Reach out to Bitly to get data using JSON
// Data parsing with internal JSON conversion

   exec sql
     select *
       into :sShortUrl
       from json_table(
              systools.httpgetclob(
                cast(
                     trim(:sReqUrl)
                     ||'&longUrl='
                     ||systools.urlencode(trim(:sPayLoad),'UTF-8')
                     as clob(200k)
                    ),
                trim(:sHeader)
              ), '$'
              columns (
                id varchar(80) path '$.data.url'
             )) as x;

   checkSql(SQLCODE:*omit:*omit:*omit:*omit:cSQL_Java_Proc_Err);

   return sShortUrl;
 end-proc;

//-------------------------------------------------------------
// Expand a shortened URL back to regular URL
// Shortening service provider is Bitly
//-------------------------------------------------------------

 dcl-proc getBitlyLong  export;
   dcl-pi *n            varchar(1024);
     sShortUrl          varchar(80) const;
   end-pi;

   dcl-s sPayLoad       varchar(80);
   dcl-s sReqUrl        varchar(1024);
   dcl-s sHeader        varchar(1024);
   dcl-s sLongUrl       varchar(1024);

// Add jvm environment
   addJvmEnvVar();

// Construct request header
   sHeader = '<httpHeader>'+
             '<header name="Content-Type" value="application/json"/>'+
             '</httpHeader>';

// Assemble the request URL
   sReqUrl = %trim(sBitUrl)+'/expand'+'?access_token='+%trim(sBitToken);
   sPayLoad = sShortUrl;

// Reach out to GOOGLE to get data using JSON
// Data parsing with internal JSON conversion
   exec sql
     select *
       into :sLongUrl
       from json_table(
              systools.httpgetclob(
                cast(
                     trim(:sReqUrl)
                     ||'&shortUrl='
                     ||systools.urlencode(trim(:sPayLoad),'UTF-8')
                     as clob(200k)
                    ),
                trim(:sHeader)
              ), '$.data.expand'
              columns (
                id varchar(1024) path '$.long_url'
             )) as x;
   checkSql(SQLCODE:*omit:*omit:*omit:*omit:cSQL_Java_Proc_Err);

   return sLongUrl;
 end-proc;

 
