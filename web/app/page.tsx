import Site, { Header } from "@/components/Site";
import { buildModel } from "@/lib/model";
import { getDB, listFlavors, type Meta } from "@/lib/store";

export const dynamic = "force-dynamic";

function Message({ text, flavors = [] }: { text: string; flavors?: Meta[] }) {
  return <div className="wrap"><Header flavors={flavors} /><p className="loading">{text}</p></div>;
}

export default async function Page({ searchParams }: { searchParams: Promise<{ v?: string }> }) {
  const { v } = await searchParams;
  let flavors: Meta[];
  try {
    flavors = await listFlavors();
  } catch (e) {
    console.error(e);
    return <Message text="Kunne ikke kontakte databasen." />;
  }
  if (!flavors.length) return <Message text="Ingen data endnu. Start WC4ever Sync og log ud af WoW (eller skriv /reload)." />;
  const meta = flavors.find((f) => f.flavor === v) || flavors.find((f) => f.flavor === "_forever_") || flavors[0];
  const db = await getDB(meta.flavor, meta);
  if (!db) return <Message text="Filen indeholder ikke WC4ever-data." flavors={flavors} />;
  return <Site m={buildModel(db)} flavors={flavors} meta={meta} />;
}
