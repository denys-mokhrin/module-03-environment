import express, { Request, Response } from 'express';
import { health } from './health.ts';

const app = express();
const port = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;

app.use(express.json());

app.get('/', (_req: Request, res: Response) => {
  res.json({ message: 'Hello from module-03-environment' });
});

app.get('/health', (_req: Request, res: Response) => {
  res.json(health(process.uptime()));
});

app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
