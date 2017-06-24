-- MySQL dump 10.13  Distrib 5.5.49, for debian-linux-gnu (x86_64)
--
-- Host: localhost    Database: exsite4
-- ------------------------------------------------------
-- Server version	5.5.49-0ubuntu0.12.04.1-log

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `content_type`
--

DROP TABLE IF EXISTS `content_type`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `content_type` (
  `content_type_id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(40) DEFAULT NULL,
  `publish_as` varchar(20) DEFAULT NULL,
  `class` varchar(40) DEFAULT NULL,
  `role` varchar(40) DEFAULT NULL,
  `subpublish` varchar(20) DEFAULT NULL,
  `navtype` varchar(20) DEFAULT NULL,
  `displaytype` varchar(20) DEFAULT NULL,
  `publish` varchar(20) DEFAULT NULL,
  `plugin` varchar(40) DEFAULT NULL,
  `revtype` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`content_type_id`)
) ENGINE=MyISAM AUTO_INCREMENT=26 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `content_type`
--

LOCK TABLES `content_type` WRITE;
/*!40000 ALTER TABLE `content_type` DISABLE KEYS */;
INSERT INTO `content_type` VALUES (1,'section','directory','ExSite::Section','','page','page','formatted','static',NULL,'template'),(2,'page','directory','ExSite::Page','','other','page','formatted','static',NULL,'template'),(3,'content','file','ExSite::Content','','none','other','raw','static',NULL,'content'),(4,'template','directory','ExSite::Template','','other','none','none','static',NULL,'template'),(5,'library','directory','ExSite::Library','','other','none','none','static',NULL,'none'),(6,'article','file','ExSite::Article','','other','item','formatted','static',NULL,'content'),(7,'blog','directory','ExSite::Blog','','item','page','formatted','static','Modules::Blog','content-index'),(8,'calendar','directory','ExSite::Calendar','','item','page','formatted','static','Modules::Calendar','content-index'),(9,'event','file','ExSite::Event','','other','item','formatted','static','Modules::Calendar','content-index'),(10,'category','directory','ExSite::Category','','other','item','formatted','static','','content'),(11,'catalog','directory','ExSite::Catalog','editorial','all','page','formatted','static','Modules::Catalog','content-index'),(12,'product','directory','ExSite::Product','editorial','all','item','formatted','static','Modules::Catalog','content'),(13,'comment','file','ExSite::Comment','','other','item','formatted','static',NULL,'content'),(14,'index','directory','ExSite::Index','editorial','item','page','formatted','static','','content-index'),(15,'keyword','file','ExSite::Keyword','editorial','none','item','formatted','static',NULL,'content'),(16,'alias','never','ExSite::Content','editorial','none','none','none','never',NULL,'none'),(17,'forum','directory','ExSite::Forum','editorial','item','page','formatted','dynamic','Modules::Forum','content-index'),(18,'location','file','Modules::Location::Location','editorial','item','item','formatted','static','Modules::Locations','content'),(19,'location_directory','directory','Modules::Location::Directory','editorial','item','page','formatted','static','Modules::Locations','content-index'),(20,'form','never','Modules::Forms::Form','editorial','all','page','formatted','dynamic','Modules::Forms','content'),(21,'question','never','Modules::Forms::Question','editorial','all','none','formatted','never','Modules::Forms','content'),(22,'fee','never','Modules::Registration::Fee','editorial','all','item','formatted','','Modules::Register','content'),(23,'album','directory','ExSite::Album','editorial','all','page','formatted','static','Modules::PhotoAlbum','index-content'),(24,'membership_type','directory','Modules::Membership::Type','editorial','all','page','formatted','static','Modules::Membership','content-index'),(25,'profile','directory','Modules::Membership::Profile','user','item','item','formatted','static','Modules::Membership','content-index');
/*!40000 ALTER TABLE `content_type` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `content_rel`
--

DROP TABLE IF EXISTS `content_rel`;
/*!40101 SET @saved_cs_client     = @@character_set_client */;
/*!40101 SET character_set_client = utf8 */;
CREATE TABLE `content_rel` (
  `content_rel_id` int(11) NOT NULL AUTO_INCREMENT,
  `type` int(11) NOT NULL DEFAULT '0',
  `under` int(11) NOT NULL DEFAULT '0',
  PRIMARY KEY (`content_rel_id`),
  KEY `type` (`type`)
) ENGINE=MyISAM AUTO_INCREMENT=47 DEFAULT CHARSET=latin1;
/*!40101 SET character_set_client = @saved_cs_client */;

--
-- Dumping data for table `content_rel`
--

LOCK TABLES `content_rel` WRITE;
/*!40000 ALTER TABLE `content_rel` DISABLE KEYS */;
INSERT INTO `content_rel` VALUES (1,1,1),(2,2,1),(3,2,2),(4,5,1),(5,5,5),(6,4,1),(7,4,4),(8,3,1),(9,3,5),(10,3,2),(11,3,4),(12,7,1),(13,7,2),(14,6,7),(15,3,6),(16,8,1),(17,9,8),(18,3,9),(19,11,1),(20,12,11),(21,3,10),(22,3,12),(23,13,6),(24,13,12),(25,14,1),(26,15,14),(27,13,17),(28,17,1),(29,17,2),(30,13,13),(31,3,13),(32,18,19),(33,18,9),(34,19,1),(35,19,2),(36,11,11),(37,21,20),(38,20,2),(39,22,9),(40,9,9),(41,24,1),(42,24,2),(43,25,24),(44,3,25),(45,18,25),(46,20,22);
/*!40000 ALTER TABLE `content_rel` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2016-07-06 16:48:31
