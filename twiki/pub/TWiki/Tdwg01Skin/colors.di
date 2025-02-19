--- colors.css	2007-02-06 16:40:36.000000000 +0100
+++ ../../../tmp/colors.css	2007-02-13 23:06:24.000000000 +0100
@@ -31,7 +31,8 @@
 	color:#8E9195;
 }
 #patternBottomBarContents a:hover {
-	color:#FBF7E8;
+	/* color:#FBF7E8; */
+	color:#EC7600;
 }
 
 /* GENERAL HTML ELEMENTS */
@@ -56,35 +57,46 @@
 	background-color:#f8fbfc;
 }
 h1, h2, h3, h4, h5, h6 {
-	color:#a00;
+	/* color:#a00; */
+	color:#6A9832;
 }
 h1 a:link,
 h1 a:visited {
-	color:#a00;
+	/* color:#a00; */
+	color:#6A9832;
 }
 h1 a:hover {
 	color:#FBF7E8;
 }
 h2 {
-	background-color:#FDFAF3;
+	/* background-color:#FDFAF3; */
+	background-color:#F9FBF7;
 	border-color:#E2DCC8;
 }
 h3, h4, h5, h6 {
 	border-color:#E9E4D2;
 }
+/*--   links - added by Loic --*/
+a:link { color: #CA6500; text-decoration:none; }
+a:visited { color:#CA6500; text-decoration:none; }
+a:hover { color:#CA6500; text-decoration:underline; }
+a:active { color:#CA6500; text-decoration:none; }
+
 /* to override old Render.pm coded font color style */
 .twikiNewLink font {
 	color:inherit;
 }
 .twikiNewLink a:link sup,
 .twikiNewLink a:visited sup {
-	color:#666;
+	/* color:#666; */
 	border-color:#ccc;
 }
 .twikiNewLink a:hover sup {
+	/* 
 	background-color:#D6000F;
 	color:#FBF7E8;
 	border-color:#D6000F;
+	*/
 }
 .twikiNewLink {
 	border-color:#ccc;
@@ -100,8 +112,10 @@
 }
 :link:hover,
 :visited:hover {
+	/*
 	color:#FBF7E8;
 	background-color:#D6000F;
+	*/
 }
 :link:hover img,
 :visited:hover img {
@@ -113,10 +127,10 @@
 	background:#fff;
 }
 .patternTopic a:visited {
-	color:#666;
+	/* color:#666; */
 }
 .patternTopic a:hover {
-	color:#FBF7E8;
+	/* color:#FBF7E8; */
 }
 
 /* Form elements */
@@ -191,7 +205,7 @@
 /* TipsContrib - in left bar */
 #patternLeftBar .tipsOfTheDay a:link,
 #patternLeftBar .tipsOfTheDay a:visited {
-	color:#a00;
+	/* color:#a00; */
 }
 #patternLeftBar .tipsOfTheDay a:hover {
 	color:#FBF7E8;
@@ -199,7 +213,8 @@
 
 /* RevCommentPlugin */
 .revComment .patternTopicAction {
-	background-color:#FEFCF6;
+	/* background-color:#FEFCF6; */
+	background-color:#F9FBF7;
 }
 
 /*	-----------------------------------------------------------
@@ -214,7 +229,8 @@
 	color:#8E9195;
 }
 .twikiGrayText a:hover {
-	color:#FBF7E8;
+	/* color:#FBF7E8; */
+	color: #EC7600;
 }
 
 table.twikiFormTable th.twikiFormTableHRow,
@@ -336,14 +352,15 @@
 }
 #patternLeftBarContents a:link,
 #patternLeftBarContents a:visited {
-	color:#666;
+	/* color:#666; */
 }
 #patternLeftBarContents a:hover {
 	color:#FBF7E8;
 }
 #patternLeftBarContents b,
 #patternLeftBarContents strong {
-	color:#333;
+	/* color:#333; */
+	color:#FFF;
 }
 #patternLeftBarContents .patternChangeLanguage {
 	color:#8E9195;
@@ -360,7 +377,7 @@
 #patternLeftBarContents .patternLeftBarPersonal a:hover,
 #patternLeftBarContents .twikiHierarchicalNavigation a:hover {
 	color:#FBF7E8;
-	background-color:#D6000F;
+	/* background-color:#D6000F; */
 }
 #patternLeftBarContents .twikiHierarchicalNavigation {
 	background:#fff;
@@ -371,7 +388,8 @@
 .patternTopicAction {
 	color:#666;
 	border-color:#E2DCC8;
-	background-color:#FCF8EC;
+	/* background-color:#FCF8EC; */
+	background-color:#F9FBF7;
 }
 .patternTopicAction s,
 .patternTopicAction strike {
@@ -382,14 +400,16 @@
 }
 .patternActionButtons a:link,
 .patternActionButtons a:visited {
-	color:#D6000F;
+	/* color:#D6000F; */
 }
 .patternActionButtons a:hover {
-	color:#FBF7E8;
+	/* color:#FBF7E8; */
 }
 .patternTopicAction .twikiAccessKey {
-	color:#D6000F;
-	border-color:#D6000F;
+	/* color:#D6000F;
+	border-color:#D6000F; */
+	color:#CA6500;
+	border-color:#CA6500;
 }
 .patternTopicAction label {
 	color:#000;
@@ -419,9 +439,11 @@
 	border-color:#e0e0e0;
 }
 .patternToolBar .patternButton a:hover {
-	background-color:#D6000F;
+	/* background-color:#D6000F; */
+	background-color:#CA6500;
 	color:#FBF7E8;
-	border-color:#D6000F;
+	/* border-color:#D6000F; */
+	border-color:#CA6500;
 }
 .patternToolBar .patternButton img {
 	background-color:transparent;
@@ -445,7 +467,8 @@
 	color:#8E9195;
 }
 .patternRevInfo a:hover {
-	color:#FBF7E8;
+	/* color:#FBF7E8; */
+	color:#CA6500;
 }
 
 .patternMoved,
@@ -454,7 +477,8 @@
 	color:#8E9195;
 }
 .patternMoved a:hover {
-	color:#FBF7E8;
+	/* color:#FBF7E8; */
+	color:#CA6500;
 }
 .patternSaveHelp {
 	background-color:#fff;
