import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import {
  build,
  UBL_GENERATOR_VERSION as GENERATOR,
  UBL_STANDARD_VERSION as STANDARD,
} from "./ubl.ts";
const fail=(m:string)=>{throw new Error("Cannot generate ZATCA XML: "+m)};
Deno.serve(async(req)=>{
 try{
  if(req.method!=="POST")return new Response("Method not allowed",{status:405});
  const auth=req.headers.get("Authorization");if(!auth) return new Response(JSON.stringify({error:"Unauthorized"}),{status:401});
  const token=auth.replace(/^Bearer\s+/,"");
  const url=Deno.env.get("SUPABASE_URL")!, key=Deno.env.get("SUPABASE_ANON_KEY")!;
  const sb=createClient(url,key,{global:{headers:{Authorization:auth}}});
  const {data:{user},error:ue}=await sb.auth.getUser(token);if(ue||!user)return new Response(JSON.stringify({error:"Unauthorized"}),{status:401});
  const {invoice_id}=await req.json();if(!invoice_id)fail("Missing invoice_id");
  const {data:i,error:ie}=await sb.from("invoices").select("*").eq("id",invoice_id).single();if(ie||!i)fail("Invoice not found or access denied");
  const {data:lines,error:le}=await sb.from("invoice_lines").select("*").eq("invoice_id",invoice_id).order("line_no");if(le)throw le;
  if(i.xml_content)return new Response(JSON.stringify({invoice_id,xml:i.xml_content,xml_standard_version:i.xml_standard_version,xml_generator_version:i.xml_generator_version,cached:true}),{headers:{"content-type":"application/json"}});
  const xml=build(i,lines||[]);
  const {data:stored,error:up}=await sb.from("invoices").update({xml_content:xml,xml_standard_version:STANDARD,xml_generator_version:GENERATOR,xml_generated_at:new Date().toISOString()}).eq("id",invoice_id).is("xml_content",null).select("xml_content,xml_standard_version,xml_generator_version").maybeSingle();if(up)throw up;
  if(!stored){
   const {data:cached,error:ce}=await sb.from("invoices").select("xml_content,xml_standard_version,xml_generator_version").eq("id",invoice_id).single();if(ce||!cached?.xml_content)throw ce||new Error("Concurrent XML generation did not persist a result");
   return new Response(JSON.stringify({invoice_id,xml:cached.xml_content,xml_standard_version:cached.xml_standard_version,xml_generator_version:cached.xml_generator_version,cached:true}),{headers:{"content-type":"application/json"}});
  }
  return new Response(JSON.stringify({invoice_id,xml:stored.xml_content,xml_standard_version:stored.xml_standard_version,xml_generator_version:stored.xml_generator_version,cached:false}),{headers:{"content-type":"application/json"}});
 }catch(e){console.error(e);return new Response(JSON.stringify({error:e instanceof Error?e.message:String(e)}),{status:422,headers:{"content-type":"application/json"}})}
});
