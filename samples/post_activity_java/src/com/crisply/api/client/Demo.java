
package com.crisply.api.client;

import com.crisply.api.rest.ActivityItem;
import com.crisply.api.rest.ObjectFactory;
import com.crisply.api.rest.Project;
import com.crisply.api.rest.Projects;
import java.io.BufferedReader;
import java.io.DataOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.StringWriter;
import java.math.BigInteger;
import java.net.URL;
import java.util.GregorianCalendar;
import javax.net.ssl.HttpsURLConnection;
import javax.xml.bind.JAXBContext;
import javax.xml.bind.JAXBElement;
import javax.xml.bind.Marshaller;
import javax.xml.bind.Unmarshaller;
import javax.xml.datatype.DatatypeFactory;
import org.apache.commons.cli.BasicParser;
import org.apache.commons.cli.CommandLine;
import org.apache.commons.cli.CommandLineParser;
import org.apache.commons.cli.HelpFormatter;
import org.apache.commons.cli.Option;
import org.apache.commons.cli.Options;
import org.apache.commons.cli.ParseException;
import org.apache.commons.codec.binary.Base64;

public class Demo {

    public static void getProjects(String subdomain, String apiKey){
        String accountUrl = "https://" + subdomain;

        HttpsURLConnection connection = null;
        try{
            URL url = new URL(accountUrl + "/timesheet/api/projects.xml");
            System.setProperty ("jsse.enableSNIExtension", "false");
	    connection = (HttpsURLConnection)url.openConnection();
            connection.setRequestMethod("GET");
            connection.setRequestProperty("Content-Type", "application/xml");

            String userpass = apiKey + ": ";
            String basicAuth = "Basic " + new String(new Base64().encode(userpass.getBytes()));
            connection.setRequestProperty ("Authorization", basicAuth);

            connection.connect();
            InputStream in = connection.getInputStream();
            JAXBContext jc = JAXBContext.newInstance("com.crisply.api.rest");
            Unmarshaller u = jc.createUnmarshaller();

            JAXBElement element = (JAXBElement)u.unmarshal(in);
            Projects projects = (Projects)element.getValue();

            printResults(projects);

        } catch (IOException ioe) {
            InputStream is;
            is = connection.getErrorStream();
            try{
                System.err.println("There was a problem getting project list: " + ioe.getMessage());
                String response = getResponseFromStream(is);
                System.out.println(response);
                ioe.printStackTrace(System.err);
            } catch (IOException responseIoe){
                responseIoe.printStackTrace(System.err);
            }
        } catch (Exception e){
            System.err.println("There was a problem getting project list:");
            e.printStackTrace(System.err);
        }
    }

    private static void printResults(Projects projects) {
        // NOTE: The projects response is paginated.  We are only displaying the
        // first page of results.
        System.out.println("Your Account Projects:");
        String headerFormat = "%7s  %-9s  %-20s%n";

        System.out.printf(headerFormat, "Id", "Status", "Name");
        System.out.printf(headerFormat, "======", "========", "==========");
        for(Project project : projects.getProject()){
            System.out.printf("%7d  %-9s  %-20s%n", project.getId(), project.getStatus(),  project.getName());
        }

        System.out.printf(headerFormat, "======", "========", "==========");

        System.out.println("");
        System.out.println("Projects Listed: " + projects.getCount() + " of " + projects.getTotal());

        if (projects.getCount().compareTo(projects.getTotal()) == -1) {
            System.out.println("NOTE: The projects response is paginated.  We are only displaying the first page of results.");
        }
    }

    public static void postActivity(String description, Long projectId, String subdomain, String apiKey){
        String accountUrl = "https://" + subdomain;

        try{
            ActivityItem activityItem = new ActivityItem();
            activityItem.setText(description);
            activityItem.setDate(DatatypeFactory.newInstance().newXMLGregorianCalendar(new GregorianCalendar()));
            activityItem.setType("document");
            activityItem.setGuid(java.util.UUID.randomUUID().toString());

            if (projectId != null){
                activityItem.setProjectId(BigInteger.valueOf(projectId));
            }

            JAXBContext jc = JAXBContext.newInstance("com.crisply.api.rest");
            Marshaller m = jc.createMarshaller();

            StringWriter writer = new StringWriter();
            ObjectFactory factory = new ObjectFactory();
            m.marshal(factory.createActivityItem(activityItem), writer);

            String content = writer.toString();
            URL url = new URL(accountUrl + "/timesheet/api/activity_items.xml");
	    HttpsURLConnection connection = (HttpsURLConnection)url.openConnection();
            System.setProperty ("jsse.enableSNIExtension", "false");
            connection.setRequestMethod("POST");
            connection.setRequestProperty("Content-Type", "application/xml");

            connection.setRequestProperty("Content-Length", "" + Integer.toString(content.getBytes().length));

            connection.setUseCaches (false);
            connection.setDoInput(true);
            connection.setDoOutput(true);

            String userpass = apiKey + ": ";
            String basicAuth = "Basic " + new String(new Base64().encode(userpass.getBytes()));
            connection.setRequestProperty ("Authorization", basicAuth);

            //Send request
            DataOutputStream outputStream = new DataOutputStream (connection.getOutputStream ());
            outputStream.writeBytes (content);
            outputStream.flush ();
            outputStream.close ();

            int statusCode = connection.getResponseCode();

            if ((statusCode >= 200) && (statusCode < 300)){
                // All went well
                System.out.println("Activity Item Created.");
            } else {
                //Get Response if there was an error status
                InputStream is;
                is = connection.getErrorStream();
                String response = getResponseFromStream(is);
                System.err.println("Error Creating Crisply Activity: \n" + response);
            }

            
        } catch (Exception ex) {
            System.err.println("Problem Creating Crisply Activity: ");
            ex.printStackTrace(System.err);
        }
    }

    public static void main(String[] args) {
        Options options = new Options();
        options.addOption("GET", false, "Get list of projects for your Crisply account.");
        options.addOption("POST", false, "Post activity to your Crisply account.");
        options.addOption("text", true, "Text of the activity item to post.");
        options.addOption("help", false, "Print this message");
        options.addOption("projectid", true, "Id of the project you want to post activity to");

        Option subdomainOption = new Option("subdomain", true, "(Required). Your Account subdomain.  Example: myaccount.crisply.com");
        subdomainOption.setRequired(true);
        options.addOption(subdomainOption);

        Option apiKeyOption = new Option("apikey", true, "(Required). Your Crisply User API Key (found on your Crisply profile page)");
        apiKeyOption.setRequired(true);
        options.addOption(apiKeyOption);

        CommandLineParser parser = new BasicParser();
        try {
            CommandLine cmd = parser.parse( options, args);

            if ((cmd.hasOption("help")) || ((!cmd.hasOption("GET")) && (!cmd.hasOption("POST"))))  {
                printUsage(options);
            }

            if (cmd.hasOption("GET")) {
                getProjects(cmd.getOptionValue("subdomain"), cmd.getOptionValue("apikey"));
            }

            if (cmd.hasOption("POST")) {
                String text = cmd.getOptionValue("text", "Activity Performed!");

                Long projectId = null;
                try {
                    projectId = Long.parseLong(cmd.getOptionValue("projectid"));
                } catch (NumberFormatException nfe) {
                    // we just won't set the project ID
                }
                postActivity(text, projectId, cmd.getOptionValue("subdomain"), cmd.getOptionValue("apikey"));
            }
        } catch (ParseException pe) {
            System.out.println(pe.getMessage());
            printUsage(options);
        }
    }

    private static void printUsage(Options options){
        HelpFormatter formatter = new HelpFormatter();
        formatter.printHelp( "-GET -POST -apikey <apikey> -subdomain <subdomain>", options );
    }

    private static String getResponseFromStream(InputStream is) throws IOException{
        if (is == null)
            return "";
        BufferedReader rd = new BufferedReader(new InputStreamReader(is));
        String line;
        StringBuilder resp = new StringBuilder();
        while((line = rd.readLine()) != null) {
            resp.append(line);
            resp.append('\n');
        }
        rd.close();

        return resp.toString();
    }

}
