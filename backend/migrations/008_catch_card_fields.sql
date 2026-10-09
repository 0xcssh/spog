-- Ce qu'il faut pour redessiner une carte sur un autre iPhone (restauration par le compte
-- Apple) : son numéro dans le garage, sa teinte et sa cote. Jusque-là, le serveur ne
-- gardait que ce qui sert au classement, et une carte restaurée n'aurait eu ni l'un ni
-- l'autre.
--
-- Colonnes nullables, sans valeur par défaut : les prises déjà en base restent valides, et
-- les anciens builds, qui ne les envoient pas, continuent de marcher. L'app retombe alors
-- sur une numérotation et une teinte déduites.
-- Idempotent : peut être rejoué sur une base existante.

alter table public.catches add column if not exists serial         integer;
alter table public.catches add column if not exists paint          bigint;   -- 0xRRGGBB
alter table public.catches add column if not exists price_low      bigint;   -- bigint : 3 M$ en dongs dépassent un int
alter table public.catches add column if not exists price_high     bigint;
alter table public.catches add column if not exists price_currency text;     -- ISO 4217
